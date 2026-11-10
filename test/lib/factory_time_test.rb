# Runs without Rails or a database:
#   ruby -Ilib test/lib/factory_time_test.rb
require "minitest/autorun"
require "time"
require_relative "../../lib/attribution/factory_time"

class FactoryTimeTest < Minitest::Test
  T0 = Time.parse("2026-11-10 08:00:00 -0600")
  DAY = (T0..(T0 + 12 * 3600))

  def run_on(item, from_min, to_min) = Attribution::FactoryTime::Run.new(work_item_id: item, started_at: T0 + from_min * 60, ended_at: to_min && T0 + to_min * 60)
  def at(min) = T0 + min * 60
  def factory_time(**kw) = Attribution::FactoryTime.call(window: DAY, **kw)

  def test_a_ticket_is_timed_from_its_agent_runs
    assert_equal({ 1 => 90 * 60 }, factory_time(runs: [run_on(1, 0, 30), run_on(1, 60, 120)]))
  end

  def test_overlapping_runs_on_one_ticket_count_once
    assert_equal({ 1 => 60 * 60 }, factory_time(runs: [run_on(1, 0, 45), run_on(1, 30, 60)]))
  end

  def test_tickets_running_at_once_share_that_time_by_default
    # Ticket 1: 0-60, ticket 2: 30-90. 0-30 → 1 alone, 30-60 shared, 60-90 → 2 alone.
    result = factory_time(runs: [run_on(1, 0, 60), run_on(2, 30, 90)])
    assert_equal 45 * 60, result[1]
    assert_equal 45 * 60, result[2]
    assert_equal 90 * 60, result.values.sum, "never more than the 90 minutes that passed"
  end

  def test_each_ticket_can_get_its_full_time_instead
    result = factory_time(runs: [run_on(1, 0, 60), run_on(2, 30, 90)], share: false)
    assert_equal({ 1 => 60 * 60, 2 => 60 * 60 }, result)
  end

  def test_time_already_tracked_by_hand_is_left_out
    result = factory_time(runs: [run_on(1, 0, 60)], exclude: [[at(20), at(30)]])
    assert_equal({ 1 => 50 * 60 }, result)
  end

  def test_idle_time_is_not_counted
    result = factory_time(runs: [run_on(1, 0, 10), run_on(2, 300, 310)])
    assert_equal 20 * 60, result.values.sum
  end

  def test_runs_are_clipped_to_the_day
    result = factory_time(runs: [run_on(1, -120, 30), run_on(2, 700, 900)])
    assert_equal 30 * 60, result[1]
    assert_equal 20 * 60, result[2]
  end

  def test_runs_without_an_end_are_ignored
    assert_empty factory_time(runs: [run_on(1, 0, nil)])
  end
end
