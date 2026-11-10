module ForemanApi
  # For each recent ticket in the ledger, asks Foreman what it knows about that
  # Jira story (its inferred run, and the engine's timeline where one exists)
  # and stores it on ForemanRun. Only reads; see ForemanApi.
  class Sync
    JIRA_KEY = /\A[A-Z][A-Z0-9]+-\d+\z/
    LOOKBACK = 30.days
    MAX_TICKETS = 300

    Outcome = Struct.new(:ok, :message, :counts, keyword_init: true)

    def self.call(client: Client.new, setting: LedgerSetting.current, now: Time.current) = new(client, setting, now).call

    def initialize(client, setting, now)
      @client = client
      @setting = setting
      @now = now
      @counts = Hash.new(0)
      @timeline_note = nil
    end

    def call
      return Outcome.new(ok: false, message: "Not signed in to Foreman (or the sign-in expired). Sign in from Settings.", counts: {}) unless ForemanApi.signed_in?(@setting)

      tickets.each do |item|
        @counts[:checked] += 1
        sync_ticket(item)
      end

      summary = "Checked #{@counts[:checked]} #{'ticket'.pluralize(@counts[:checked])} in Foreman: " \
                "#{@counts[:followed]} followed, #{@counts[:not_followed]} not followed by Foreman." \
                "#{" #{@timeline_note}" if @timeline_note}"
      @setting.update!(foreman_last_synced_at: @now, foreman_last_sync_summary: summary, foreman_sync_error: nil)
      Outcome.new(ok: true, message: summary, counts: @counts.to_h)
    rescue Client::Error => e
      @setting.update!(foreman_sync_error: e.message)
      Outcome.new(ok: false, message: "Foreman sync stopped: #{e.message}", counts: @counts.to_h)
    end

    private

      # Recent tickets with a Jira-style key (TIME-1, ACME-102, …).
      def tickets
        WorkItem.where("updated_at >= ? OR status NOT IN (?)", @now - LOOKBACK, %w[done cancelled])
                .order(updated_at: :desc).limit(MAX_TICKETS).select { |item| item.jira_key.match?(JIRA_KEY) }
      end

      def sync_ticket(item)
        record = ForemanRun.find_or_initialize_by(work_item: item)
        run = begin
          @client.inferred_run(item.jira_key)
        rescue Client::Error => e
          raise unless e.not_found?

          nil
        end

        if run.nil?
          @counts[:not_followed] += 1
          return record.update!(followed: false, run_id: nil, tasks: [], fetched_at: @now)
        end

        data = run["run"] || {}
        @counts[:followed] += 1
        record.update!(
          followed: true, run_id: data["id"], workflow: data["workflow"], workflow_version: data["workflow_version"],
          client: data["client"], position: data["position"], status: data["status"], state: data["state"],
          dormant: data["dormant"] == true, tasks: Array(data["tasks"]), timeline: timeline_for(item.jira_key, record),
          run_started_at: data["started_at"], run_ended_at: data["ended_at"], foreman_built_at: run["build"], fetched_at: @now
        )
      end

      # The engine timeline needs a granted scope. Without one, stop asking for
      # the rest of this sync and say so once in the summary.
      def timeline_for(key, record)
        return record.timeline || [] if @timeline_note

        Array(@client.story_timeline(key)["entries"])
      rescue Client::Error => e
        if e.forbidden?
          @timeline_note = "Step-by-step timelines need a granted scope in Foreman; the steps below still show."
          record.timeline || []
        elsif e.not_found?
          [] # the engine hasn't run this story yet; inferred steps still show
        else
          raise
        end
      end
  end
end
