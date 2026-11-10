# What Foreman infers about one ticket's process: the workflow it follows, the
# step it's at, and every visit to a step with when it was entered, claimed,
# and left. Wait = entered → claimed. Work = claimed → left.
class ForemanRun < ApplicationRecord
  belongs_to :work_item

  STATE_LABELS = {
    "working" => "being worked on", "unclassified" => "waiting (no claim seen)", "external" => "with someone outside Twin Sun",
    "held" => "on hold", "unmapped" => "in a status Foreman doesn't map", "completed" => "completed"
  }.freeze

  def state_label = STATE_LABELS.fetch(state.to_s, state.to_s.humanize)

  def steps = Array(tasks).map { |t| Step.new(t) }

  def total_wait_seconds(now: Time.current) = steps.sum { |s| s.wait_seconds(now:) }
  def total_work_seconds(now: Time.current) = steps.sum { |s| s.work_seconds(now:) }

  # One visit to a step, from Foreman's inferred-run `tasks`.
  class Step
    attr_reader :raw

    def initialize(raw) = @raw = raw.to_h

    def node = raw["node"]
    def contract = raw["contract"]
    def outcome = raw["outcome"] || raw["error"]
    def implementor = raw["implementor"]
    def implementor_type = raw["implementor_type"]
    def claim_source = raw["claim_source"]
    def entered_at = parse(raw["enqueued_at"])
    def claimed_at = parse(raw["claimed_at"])
    def left_at = parse(raw["ended_at"])
    def open? = left_at.nil?

    # Waiting for someone to pick it up: entered → claimed (or → left/now when never claimed).
    def wait_seconds(now: Time.current)
      return 0 unless entered_at

      [(claimed_at || left_at || now) - entered_at, 0].max.to_i
    end

    # Being worked on: claimed → left (or → now while still open).
    def work_seconds(now: Time.current)
      return 0 unless claimed_at

      [(left_at || now) - claimed_at, 0].max.to_i
    end

    def mine?(harvest_user_id) = harvest_user_id.present? && implementor.to_s == harvest_user_id.to_s

    private

      def parse(value) = value.present? ? Time.zone.parse(value.to_s) : nil
  end
end
