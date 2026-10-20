class AttentionSpan < ApplicationRecord
  belongs_to :person
  belongs_to :work_item, optional: true
  belongs_to :batch, optional: true

  validates :activity, inclusion: { in: Activity::ALL }
  validates :started_at, :last_seen_at, presence: true

  scope :overlapping, ->(range) { where("started_at < ? AND last_seen_at > ?", range.end, range.begin) }

  def seconds = (last_seen_at - started_at).to_i

  def target_label
    if work_item then work_item.jira_key
    elsif batch then "#{batch.display_name} (overhead)"
    else "Unattributed"
    end
  end

  # A heartbeat says "this person is actively working on this target now".
  # It extends their open span if the target and activity match and the last
  # heartbeat was within the idle gap; otherwise it starts a new span.
  def self.record_heartbeat!(person:, activity:, at: Time.current, work_item: nil, batch: nil, idle_gap: LedgerSetting.current.idle_gap)
    batch = nil if work_item # time on a ticket is direct, never batch overhead
    transaction do
      last = person.attention_spans.lock.order(last_seen_at: :desc).first
      same_target = last &&
                    last.work_item_id == work_item&.id &&
                    last.batch_id == batch&.id &&
                    last.activity == activity
      if same_target && at >= last.last_seen_at && at - last.last_seen_at <= idle_gap
        last.update!(last_seen_at: at)
        last
      else
        create!(person:, work_item:, batch:, activity:, started_at: at, last_seen_at: at)
      end
    end
  end
end
