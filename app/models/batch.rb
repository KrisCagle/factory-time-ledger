class Batch < ApplicationRecord
  belongs_to :started_by, class_name: "Person", optional: true
  has_many :work_items, dependent: :nullify
  has_many :attention_spans, dependent: :nullify

  validates :source, :external_id, :started_at, presence: true

  def display_name = label.presence || "Batch #{external_id}"

  # Human time spent on the batch as a whole (not on any one ticket).
  def overhead_seconds = attention_spans.where(work_item_id: nil).sum(&:seconds)
end
