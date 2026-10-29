module Scarif
  # Reads recently changed Scarif work items and records them in the ledger,
  # through EventIngest like any other factory:
  #
  #   work item          → ticket (Jira key, summary, repo, agent points, status)
  #   node runs / stages → agent runs with timing (and cost, for factory items)
  #   factory asks       → "waiting on a human" / "human answered", plus review
  #                        approvals and rework (approve / revise, reject)
  #   enqueued together  → a batch (same person, each within BATCH_GAP of the last)
  #
  # Event IDs are derived from Scarif's IDs, so re-reading an item never
  # duplicates anything. Only items updated since the last sync are re-read.
  class Sync
    SOURCE = "scarif".freeze
    BATCH_GAP = 10.minutes
    OVERLAP = 10.minutes # re-read a little before the last sync, to be safe
    MAX_PAGES = 25

    STATUS_MAP = {
      "queued" => "queued", "dependency_wait" => "queued",
      "planning" => "in_progress", "in_progress" => "in_progress", "review" => "in_progress",
      "evaluating" => "in_progress", "verify" => "in_progress", "split_wait" => "in_progress",
      "plan_approval" => "waiting_on_human", "human_review" => "waiting_on_human", "blocked" => "waiting_on_human",
      "done" => "done", "decomposed" => "done", "cancelled" => "cancelled"
    }.freeze

    APPROVED = %w[approve].freeze
    SENT_BACK = %w[revise reject].freeze

    Outcome = Struct.new(:ok, :message, :counts, keyword_init: true)

    def self.call(client: Client.new, setting: LedgerSetting.current, now: Time.current) = new(client, setting, now).call

    def initialize(client, setting, now)
      @client = client
      @setting = setting
      @now = now
      @counts = Hash.new(0)
    end

    def call
      return Outcome.new(ok: false, message: "Scarif isn't connected. Add SCARIF_API_TOKEN to .env and restart.", counts: {}) unless Client.configured?

      if @setting.scarif_user_id.blank?
        check = CheckConnection.call(client: @client, setting: @setting)
        return Outcome.new(ok: false, message: check.message, counts: {}) unless check.ok
      end

      each_recent_item do |item|
        @counts[:read] += 1
        next @counts[:not_mine] += 1 unless mine?(item)

        record = ExternalRecord.find_or_initialize_by(source: SOURCE, external_id: item["id"].to_s)
        next @counts[:unchanged] += 1 if unchanged?(record, item)

        import(item, record)
        @counts[:updated] += 1
      end
      infer_batches

      summary = "Read #{@counts[:read]} recently changed Scarif #{'item'.pluralize(@counts[:read])}; " \
                "#{@counts[:updated]} updated, #{@counts[:unchanged]} unchanged" \
                "#{", #{@counts[:not_mine]} skipped (not yours)" if @counts[:not_mine].positive?}."
      @setting.update!(scarif_last_synced_at: @now, scarif_last_sync_summary: summary, scarif_sync_error: nil)
      Outcome.new(ok: true, message: summary, counts: @counts.to_h)
    rescue Client::Error, EventIngest::Invalid => e
      @setting.update!(scarif_sync_error: e.message)
      Outcome.new(ok: false, message: "Scarif sync stopped: #{e.message}", counts: @counts.to_h)
    end

    private

      # Pages newest-updated first and stops at the first item older than the cutoff.
      def each_recent_item
        cutoff = @setting.scarif_last_synced_at ? @setting.scarif_last_synced_at - OVERLAP : @now - @setting.scarif_lookback_days.days
        cursor = nil
        MAX_PAGES.times do
          page = @client.work_items(cursor:)
          page.items.each do |item|
            return if time(item["updated_at"]) && time(item["updated_at"]) < cutoff

            yield item
          end
          return unless page.has_more && page.next_cursor

          cursor = page.next_cursor
        end
      end

      def mine?(item)
        return true unless @setting.scarif_only_mine

        orderer = item["enqueued_by"]
        orderer.is_a?(Hash) && orderer["kind"] != "service_account" && orderer["id"].to_s == @setting.scarif_user_id.to_s
      end

      def unchanged?(record, item)
        record.persisted? && record.external_updated_at &&
          record.external_updated_at.to_f.round(3) == time(item["updated_at"]).to_f.round(3)
      end

      def import(item, record)
        id = item["id"].to_s
        key = item["jira_key"].presence || item["display_key"].presence || "SCARIF-#{id.first(8)}"
        detail = @client.work_item(id)
        repo = Array(detail["repositories"] || item["repositories"]).first&.dig("full_name")
        orderer_is_me = item.dig("enqueued_by", "id").to_s == @setting.scarif_user_id.to_s

        @base = {
          "source" => SOURCE, "jira_key" => key, "summary" => item["jira_summary"].presence,
          "repo" => repo, "agent_points" => item["agent_points_size"]
        }
        ingest("wi-#{id}-started", "pipeline_started", item["created_at"],
               person_email: (@setting.scarif_user_email if orderer_is_me))

        run_ids = import_runs(id, detail)
        finished_at = import_asks(id, item["jira_key"])
        finish(id, item, detail, finished_at)

        work_item = WorkItem.find_by!(jira_key: key.upcase)
        reconcile_cost(id, work_item, run_ids, item["total_cost_usd"])
        work_item.update!(status: ledger_status(item))

        record.update!(work_item:, jira_key: key, enqueued_by_id: item.dig("enqueued_by", "id")&.to_s,
                       external_created_at: time(item["created_at"]), external_updated_at: time(item["updated_at"]))
      end

      # Factory items: one agent run per node run (these carry cost).
      # Older items: one agent run per stage (timing only).
      def import_runs(id, detail)
        stages = Array(detail["stages"])
        factory = detail["factory_job"].present? || stages.any? { |s| s["stage_type"] == "factory_job" }
        runs = if factory
                 @client.node_runs(id).map do |r|
                   { ext: "node-#{r['id']}", type: r["node_id"].presence || r["kind"], status: r["status"],
                     started_at: r["started_at"], completed_at: r["completed_at"], cost: r["cost_usd"] }
                 end
               else
                 stages.map do |s|
                   { ext: "stage-#{s['id']}", type: s["stage_type"], status: s["status"],
                     started_at: s["started_at"], completed_at: s["completed_at"], cost: nil }
                 end
               end

        runs.each do |run|
          next if run[:started_at].blank?

          data = { "stage_id" => run[:ext], "stage_type" => run[:type] }
          ingest("#{run[:ext]}-claimed", "stage_claimed", run[:started_at], data:)
          next if run[:completed_at].blank?

          type = case run[:status].to_s
                 when "failed" then "stage_failed"
                 when "cancelled", "canceled" then "stage_cancelled"
                 else "stage_completed"
                 end
          ingest("#{run[:ext]}-done", type, run[:completed_at], data: data.merge("cost_usd" => run[:cost]).compact)
        end
        runs.map { |run| run[:ext] }
      end

      # Returns the latest answer time, if any.
      def import_asks(id, jira_key)
        return nil if jira_key.blank?

        asks = @client.factory_asks(jira_key:).select { |ask| ask["work_item_id"].to_s == id }
        asks.filter_map do |ask|
          ask_id = ask["id"]
          ingest("ask-#{ask_id}-opened", "wait_human_entered", ask["opened_at"],
                 data: { "reason" => ask["kind"], "node_id" => ask["node_id"] }.compact)
          next if ask["answered_at"].blank?

          person = ask["answered_by"].to_s.include?("@") ? ask["answered_by"] : nil
          resolution = ask["resolution"].to_s
          ingest("ask-#{ask_id}-answered", "wait_human_resolved", ask["answered_at"],
                 person_email: person, data: { "reason" => ask["kind"], "resolution" => resolution.presence }.compact)
          if APPROVED.include?(resolution)
            ingest("ask-#{ask_id}-approved", "human_review_approved", ask["answered_at"], person_email: person)
          elsif SENT_BACK.include?(resolution)
            ingest("ask-#{ask_id}-sent-back", "human_review_changes_requested", ask["answered_at"], person_email: person,
                   data: { "reason" => resolution })
          end
          time(ask["answered_at"])
        end.max
      end

      def finish(id, item, detail, last_answer)
        status = item["status"].to_s
        return unless %w[done decomposed cancelled].include?(status)

        ends = Array(detail["stages"]).filter_map { |s| time(s["completed_at"]) } + [last_answer].compact
        at = ends.max || time(item["updated_at"])
        type = status == "cancelled" ? "pipeline_cancelled" : "pipeline_completed"
        ingest("wi-#{id}-#{type}", type, at.iso8601)
      end

      def ledger_status(item)
        return "waiting_on_human" if item["open_factory_ask"].present?

        STATUS_MAP.fetch(item["status"].to_s, "in_progress")
      end

      # Keeps the ledger's agent cost equal to Scarif's total for the item: any
      # cost Scarif reports that isn't on an itemised run goes on one adjustment row.
      def reconcile_cost(id, work_item, run_ids, total)
        adjustment = work_item.agent_runs.find_or_initialize_by(source: SOURCE, external_id: "wi-#{id}-unitemized")
        itemised = work_item.agent_runs.where(source: SOURCE, external_id: run_ids).sum(:cost_usd).to_d
        diff = total.to_d - itemised
        if total.present? && diff.abs > BigDecimal("0.005")
          adjustment.update!(stage_type: "cost not itemized by Scarif", cost_usd: diff.round(6))
        elsif adjustment.persisted?
          adjustment.destroy!
        end
      end

      def infer_batches
        since = @now - @setting.scarif_lookback_days.days
        records = ExternalRecord.where(source: SOURCE).where.not(work_item_id: nil).where.not(enqueued_by_id: nil)
                                .where(external_created_at: since..).order(:enqueued_by_id, :external_created_at).to_a
        scarif_batches = Batch.where(source: SOURCE)

        records.group_by(&:enqueued_by_id).each do |orderer_id, rows|
          clusters = rows.slice_when { |a, b| b.external_created_at - a.external_created_at > BATCH_GAP }
          clusters.each do |cluster|
            item_ids = cluster.map(&:work_item_id).uniq
            assignable = WorkItem.where(id: item_ids).where(batch_id: nil).or(WorkItem.where(id: item_ids, batch_id: scarif_batches.select(:id)))
            if item_ids.size < 2
              assignable.update_all(batch_id: nil)
              next
            end

            started = cluster.first.external_created_at
            batch = Batch.find_or_create_by!(source: SOURCE, external_id: "#{orderer_id}-#{started.to_i}") do |b|
              b.started_at = started
              b.started_by = Person.find_by(email: @setting.scarif_user_email) if orderer_id == @setting.scarif_user_id.to_s
            end
            batch.update!(label: "Scarif batch · #{started.in_time_zone.strftime('%b %-d, %-l:%M %p')} (#{item_ids.size} tickets)")
            assignable.update_all(batch_id: batch.id)
          end
        end

        Batch.where(source: SOURCE).where.missing(:work_items).find_each(&:destroy!)
      end

      def ingest(event_id, type, occurred_at, person_email: nil, data: {})
        return if occurred_at.blank?

        EventIngest.call(@base.merge(
          "event_id" => event_id, "event_type" => type, "occurred_at" => occurred_at.to_s,
          "person_email" => person_email, "data" => data
        ).compact)
      end

      def time(value) = value.present? ? Time.zone.parse(value.to_s) : nil
  end
end
