# Single-row settings table.
class LedgerSetting < ApplicationRecord
  validates :split_rule, inclusion: { in: Attribution::Engine::RULES.map(&:to_s) }
  validates :idle_gap_minutes, numericality: { only_integer: true, in: 1..60 }
  validates :rounding_minutes, numericality: { only_integer: true, in: 0..60 }

  def self.current = first_or_create!

  def idle_gap = idle_gap_minutes.minutes

  def harvest_checked? = harvest_checked_at.present? && harvest_check_error.blank?

  # Projects from Harvest are only trusted for safety checks once loaded.
  def harvest_projects_loaded? = harvest_projects_synced_at.present?
end
