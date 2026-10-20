# The kinds of human time the ledger tracks. Each maps to a Harvest task on
# the project (review and QA share the QA task).
module Activity
  ALL = %w[development review qa supervision].freeze

  LABELS = {
    "development" => "Development",
    "review" => "Review",
    "qa" => "QA",
    "supervision" => "Factory supervision"
  }.freeze

  def self.label(activity) = LABELS.fetch(activity.to_s, activity.to_s.humanize)
end
