# Takes one event from any factory and records it. The payload shape is
# documented in README.md ("Sending events"). Re-sending the same event
# (same source + event_id) is harmless.
class EventIngest
  class Invalid < StandardError; end

  Result = Struct.new(:event, :duplicate, keyword_init: true)

  REQUIRED = %w[source event_id event_type occurred_at jira_key].freeze

  def self.call(payload) = new(payload).call

  def initialize(payload)
    @payload = payload.to_h.deep_stringify_keys
  end

  def call
    missing = REQUIRED.select { |key| @payload[key].blank? }
    raise Invalid, "missing #{missing.join(', ')}" if missing.any?

    existing = PipelineEvent.find_by(source:, external_id: @payload["event_id"].to_s)
    return Result.new(event: existing, duplicate: true) if existing

    event = nil
    ActiveRecord::Base.transaction do
      person = @payload["person_email"].present? ? Person.for_email!(@payload["person_email"], name: @payload["person_name"]) : nil
      work_item = upsert_work_item(person)
      event = work_item.pipeline_events.create!(
        source:,
        external_id: @payload["event_id"].to_s,
        event_type: @payload["event_type"].to_s,
        occurred_at:,
        person:,
        data:
      )
      apply_side_effects(work_item, event)
    end
    Result.new(event:, duplicate: false)
  rescue ActiveRecord::RecordNotUnique
    Result.new(event: PipelineEvent.find_by!(source:, external_id: @payload["event_id"].to_s), duplicate: true)
  end

  private

    def source = @payload["source"].to_s
    def data = @payload["data"].is_a?(Hash) ? @payload["data"] : {}

    def occurred_at
      @occurred_at ||= Time.zone.parse(@payload["occurred_at"].to_s) || raise(Invalid, "occurred_at is not a time")
    end

    def upsert_work_item(person)
      item = WorkItem.find_or_initialize_by(jira_key: @payload["jira_key"].to_s.upcase)
      item.source = source if item.new_record?
      item.summary = @payload["summary"] if @payload["summary"].present?
      item.project = Project.for_repo!(@payload["repo"]) if @payload["repo"].present?
      item.batch = upsert_batch(person) if @payload["batch_id"].present?
      item.agent_points = Integer(@payload["agent_points"]) if @payload["agent_points"].present?
      item.enqueued_at ||= occurred_at
      item.save!
      item
    end

    def upsert_batch(person)
      Batch.find_or_create_by!(source:, external_id: @payload["batch_id"].to_s) do |batch|
        batch.label = @payload["batch_label"]
        batch.started_by = person
        batch.started_at = occurred_at
      end
    end

    def apply_side_effects(item, event)
      case event.event_type
      when "pipeline_started", "wait_human_resolved"
        item.update!(status: "in_progress") unless item.status.in?(%w[done cancelled])
      when "wait_human_entered", "escalation"
        item.update!(status: "waiting_on_human") unless item.status.in?(%w[done cancelled])
      when "pipeline_completed"
        item.update!(status: "done", completed_at: event.occurred_at)
      when "pipeline_cancelled"
        item.update!(status: "cancelled", completed_at: event.occurred_at)
      when "agent_points_recorded"
        item.update!(agent_points: Integer(data["agent_points"])) if data["agent_points"].present?
      when "stage_claimed"
        agent_run(item).update!(stage_type: data["stage_type"], started_at: event.occurred_at)
      when "stage_completed", "stage_failed", "stage_cancelled"
        run = agent_run(item)
        run.started_at ||= event.occurred_at
        run.update!(
          stage_type: data["stage_type"] || run.stage_type,
          completed_at: event.occurred_at,
          cost_usd: data["cost_usd"].presence || run.cost_usd,
          tokens: data["tokens"].presence || run.tokens
        )
      end
    end

    def agent_run(item)
      stage_id = data["stage_id"].presence || raise(Invalid, "#{@payload['event_type']} needs data.stage_id")
      item.agent_runs.find_or_initialize_by(source:, external_id: stage_id.to_s)
    end
end
