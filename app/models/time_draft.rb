class TimeDraft < ApplicationRecord
  STATUSES = %w[draft approved sent failed].freeze

  belongs_to :person
  belongs_to :work_item

  validates :activity, inclusion: { in: Activity::ALL }
  validates :status, inclusion: { in: STATUSES }
  validates :hours, numericality: { greater_than_or_equal_to: 0 }

  scope :for_day, ->(person, date) { where(person:, spent_on: date) }

  def editable? = %w[draft failed approved].include?(status)
  def total_seconds = direct_seconds + overhead_seconds
end
