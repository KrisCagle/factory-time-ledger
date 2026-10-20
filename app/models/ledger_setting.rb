# Single-row settings table.
class LedgerSetting < ApplicationRecord
  validates :split_rule, inclusion: { in: Attribution::Engine::RULES.map(&:to_s) }
  validates :idle_gap_minutes, numericality: { only_integer: true, in: 1..60 }
  validates :rounding_minutes, numericality: { only_integer: true, in: 0..60 }

  def self.current = first_or_create!

  def idle_gap = idle_gap_minutes.minutes
end
