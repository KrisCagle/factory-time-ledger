# Runs the attribution engine for one person on one day, and turns the result
# into Harvest drafts.
class DayAttribution
  attr_reader :person, :date, :setting

  def initialize(person:, date:, setting: LedgerSetting.current)
    @person = person
    @date = date
    @setting = setting
  end

  def day_range = date.in_time_zone.all_day

  # Spans overlapping the day, clipped to it.
  def spans
    @spans ||= person.attention_spans.overlapping(day_range)
                     .includes(:work_item, :batch).order(:started_at).to_a
  end

  def result
    @result ||= Attribution::Engine.call(
      spans: spans.map { |s| engine_span(s) },
      items: engine_items,
      rule: setting.split_rule
    )
  end

  def work_items_by_id
    @work_items_by_id ||= WorkItem.where(id: relevant_item_ids).includes(:project, :batch, :agent_runs).index_by(&:id)
  end

  def batches_by_id
    @batches_by_id ||= Batch.where(id: result.batch_splits.map(&:batch_id)).index_by(&:id)
  end

  # Creates or refreshes this day's drafts. Approved and sent drafts are left
  # alone so nothing a person signed off on changes underneath them; drafts
  # whose time disappeared are removed.
  def write_drafts!
    kept = []
    TimeDraft.transaction do
      result.lines.each do |line|
        draft = TimeDraft.find_or_initialize_by(person:, work_item_id: line.work_item_id, spent_on: date, activity: line.activity)
        kept << draft.id if draft.persisted?
        next if %w[approved sent].include?(draft.status)

        draft.assign_attributes(
          direct_seconds: line.direct_seconds,
          overhead_seconds: line.overhead_seconds,
          hours: Attribution::Engine.hours_for(line.total_seconds, rounding_minutes: setting.rounding_minutes),
          notes: notes_for(line),
          status: "draft",
          last_error: nil
        )
        draft.save!
        kept << draft.id
      end
      TimeDraft.for_day(person, date).where(status: %w[draft failed]).where.not(id: kept).destroy_all
    end
    TimeDraft.for_day(person, date)
  end

  def notes_for(line)
    item = work_items_by_id[line.work_item_id]
    label = [item.jira_key, item.summary].compact_blank.join(": ")
    detail = Activity.label(line.activity)
    if line.overhead_seconds.positive?
      split = result.batch_splits.find { |s| s.batch_id == item.batch_id }
      detail += ", includes #{(line.overhead_seconds / 60.0).round}m batch overhead split by #{split&.rule_used.to_s.tr('_', ' ')}"
    end
    "#{label} (#{detail}) [factory-time-ledger]"
  end

  private

    def engine_span(span)
      Attribution::Span.new(
        id: span.id,
        work_item_id: span.work_item_id,
        batch_id: span.batch_id,
        activity: span.activity,
        started_at: [span.started_at, day_range.begin].max,
        ended_at: [span.last_seen_at, day_range.end].min
      )
    end

    def relevant_item_ids
      direct = spans.filter_map(&:work_item_id)
      batch_ids = spans.filter_map(&:batch_id)
      (direct + WorkItem.where(batch_id: batch_ids).pluck(:id)).uniq
    end

    def engine_items
      WorkItem.where(id: relevant_item_ids).includes(:agent_runs).map do |item|
        Attribution::Item.new(id: item.id, batch_id: item.batch_id, agent_points: item.agent_points, agent_seconds: item.agent_seconds)
      end
    end
end
