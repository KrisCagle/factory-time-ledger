# Append-only, like Scarif's. Event names follow Scarif's vocabulary; unknown
# names are accepted (factories evolve) and just get a generic label.
class PipelineEvent < ApplicationRecord
  KNOWN_TYPES = {
    "ticket_added" => "Added by hand",
    "pipeline_started" => "Pipeline started",
    "stage_claimed" => "Agent stage claimed",
    "stage_completed" => "Agent stage completed",
    "stage_failed" => "Agent stage failed",
    "stage_cancelled" => "Agent stage cancelled",
    "agent_points_recorded" => "Agent points recorded",
    "pr_created" => "PR opened",
    "pr_merged" => "PR merged",
    "pr_closed" => "PR closed",
    "ci_check" => "CI check",
    "escalation" => "Escalated to a human",
    "wait_human_entered" => "Waiting on a human",
    "wait_human_resolved" => "Human answered",
    "human_review_approved" => "Review approved",
    "human_review_changes_requested" => "Changes requested",
    "human_review_closed" => "Review closed",
    "pipeline_completed" => "Pipeline completed",
    "pipeline_cancelled" => "Pipeline cancelled"
  }.freeze

  belongs_to :work_item
  belongs_to :person, optional: true

  validates :source, :external_id, :event_type, :occurred_at, presence: true

  before_update { raise ActiveRecord::ReadOnlyRecord, "pipeline events are append-only" }

  def label = KNOWN_TYPES.fetch(event_type, event_type.humanize)
end
