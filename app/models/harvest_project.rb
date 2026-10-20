# A Harvest project the token's owner is assigned to, with its assigned tasks.
# Refreshed from Harvest by Settings → Load from Harvest.
class HarvestProject < ApplicationRecord
  validates :harvest_id, presence: true, uniqueness: true
  validates :name, presence: true

  scope :active, -> { where(is_active: true) }
  scope :ordered, -> { order(:client_name, :name) }

  def label = [client_name, name].compact_blank.join(" — ")

  def task_ids = tasks.map { |task| task["id"].to_i }
  def has_task?(task_id) = task_ids.include?(task_id.to_i)
  def task_name(task_id) = tasks.find { |task| task["id"].to_i == task_id.to_i }&.dig("name")
end
