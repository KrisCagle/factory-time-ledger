# Runs without Rails or a database:
#   ruby -Ilib test/lib/attribution_engine_test.rb
# It also runs as part of `bin/rails test`.
require "minitest/autorun"
require "time"
require_relative "../../lib/attribution/engine"

class AttributionEngineTest < Minitest::Test
  T0 = Time.parse("2026-10-20 09:00:00 -0500")

  def span(id, start_min, end_min, item: nil, batch: nil, activity: "review")
    Attribution::Span.new(id:, work_item_id: item, batch_id: batch, activity:,
                          started_at: T0 + start_min * 60, ended_at: T0 + end_min * 60)
  end

  def item(id, batch: 1, points: nil, agent_minutes: nil)
    Attribution::Item.new(id:, batch_id: batch, agent_points: points,
                          agent_seconds: agent_minutes && agent_minutes * 60)
  end

  def line_for(result, item_id, activity)
    result.lines.find { |l| l.work_item_id == item_id && l.activity == activity }
  end

  def test_direct_time_goes_to_its_ticket
    result = Attribution::Engine.call(spans: [span(1, 0, 30, item: 10)], items: [item(10)])
    assert_equal 30 * 60, line_for(result, 10, "review").direct_seconds
    assert_equal 0, result.unattributed_seconds
  end

  def test_overlapping_spans_later_start_wins
    spans = [span(1, 0, 30, item: 10), span(2, 20, 40, item: 11)]
    result = Attribution::Engine.call(spans:, items: [item(10), item(11)])
    assert_equal 20 * 60, line_for(result, 10, "review").direct_seconds
    assert_equal 20 * 60, line_for(result, 11, "review").direct_seconds
  end

  def test_batch_overhead_split_by_agent_points
    items = [item(10, points: 1), item(11, points: 3)]
    result = Attribution::Engine.call(spans: [span(1, 0, 40, batch: 1, activity: "supervision")], items:)
    assert_equal 10 * 60, line_for(result, 10, "supervision").overhead_seconds
    assert_equal 30 * 60, line_for(result, 11, "supervision").overhead_seconds
    assert_equal :agent_points, result.batch_splits.first.rule_used
  end

  def test_unsized_ticket_falls_back_to_agent_time
    items = [item(10, points: 2, agent_minutes: 10), item(11, points: nil, agent_minutes: 30)]
    result = Attribution::Engine.call(spans: [span(1, 0, 40, batch: 1)], items:)
    assert_equal :agent_time, result.batch_splits.first.rule_used
    assert_equal 10 * 60, line_for(result, 10, "review").overhead_seconds
    assert_equal 30 * 60, line_for(result, 11, "review").overhead_seconds
  end

  def test_falls_back_to_even_when_nothing_to_weigh_by
    items = [item(10), item(11)]
    result = Attribution::Engine.call(spans: [span(1, 0, 20, batch: 1)], items:)
    assert_equal :even, result.batch_splits.first.rule_used
    assert_equal 10 * 60, line_for(result, 10, "review").overhead_seconds
  end

  def test_split_adds_back_up_exactly
    items = [item(10), item(11), item(12)]
    spans = [Attribution::Span.new(id: 1, batch_id: 1, activity: "supervision", started_at: T0, ended_at: T0 + 100)]
    result = Attribution::Engine.call(spans:, items:, rule: :even)
    assert_equal 100, result.lines.sum(&:overhead_seconds)
    assert_equal [33, 33, 34], result.lines.map(&:overhead_seconds).sort
  end

  def test_span_with_no_ticket_or_batch_is_unattributed
    result = Attribution::Engine.call(spans: [span(1, 0, 15)], items: [])
    assert_equal 15 * 60, result.unattributed_seconds
    assert_empty result.lines
  end

  def test_overhead_for_batch_with_no_tickets_is_unattributed
    result = Attribution::Engine.call(spans: [span(1, 0, 15, batch: 99)], items: [item(10, batch: 1)])
    assert_equal 15 * 60, result.unattributed_seconds
  end

  def test_direct_and_overhead_combine_on_one_line
    items = [item(10, points: 1), item(11, points: 1)]
    spans = [span(1, 0, 20, item: 10), span(2, 20, 40, batch: 1)]
    line = line_for(Attribution::Engine.call(spans:, items:), 10, "review")
    assert_equal 20 * 60, line.direct_seconds
    assert_equal 10 * 60, line.overhead_seconds
  end

  def test_hours_rounding
    assert_equal 0.5, Attribution::Engine.hours_for(30 * 60)
    assert_equal 0.1, Attribution::Engine.hours_for(7 * 60, rounding_minutes: 6)
    assert_equal 0.2, Attribution::Engine.hours_for(10 * 60, rounding_minutes: 6)
  end

  def test_rejects_unknown_rule
    assert_raises(ArgumentError) { Attribution::Engine.new(spans: [], items: [], rule: :vibes) }
  end
end
