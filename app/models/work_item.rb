class WorkItem < ApplicationRecord
  STATUSES = %w[queued in_progress waiting_on_human done cancelled].freeze

  belongs_to :project, optional: true
  belongs_to :batch, optional: true
  has_many :pipeline_events, -> { order(:occurred_at, :id) }, dependent: :destroy
  has_many :agent_runs, dependent: :destroy
  has_many :attention_spans, dependent: :nullify
  has_many :time_drafts, dependent: :destroy

  validates :jira_key, presence: true, uniqueness: true
  validates :source, presence: true
  validates :status, inclusion: { in: STATUSES }

  def agent_seconds = agent_runs.sum(&:seconds)
  def agent_cost_usd = agent_runs.sum { |run| run.cost_usd.to_d }

  # How many times a human sent it back for changes.
  def rework_count = pipeline_events.where(event_type: "human_review_changes_requested").count

  # Direct attention on this ticket, by activity, in seconds.
  def direct_seconds_by_activity
    attention_spans.group_by(&:activity).transform_values { |spans| spans.sum(&:seconds) }
  end

  # What has been drafted to Harvest (direct + share of batch overhead).
  def drafted_seconds_by_activity
    time_drafts.group_by(&:activity).transform_values { |drafts| drafts.sum { |d| d.direct_seconds + d.overhead_seconds } }
  end
end
