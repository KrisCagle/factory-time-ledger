require "test_helper"

class AttentionSpanTest < ActiveSupport::TestCase
  setup do
    EventIngest.call(event_payload)
    @person = Person.for_email!("dev@example.com")
    @item = WorkItem.find_by!(jira_key: "TEST-1")
    @t = Time.zone.parse("2026-10-20 10:00")
  end

  test "heartbeats within the idle gap extend one span" do
    AttentionSpan.record_heartbeat!(person: @person, activity: "review", work_item: @item, at: @t, idle_gap: 3.minutes)
    AttentionSpan.record_heartbeat!(person: @person, activity: "review", work_item: @item, at: @t + 60, idle_gap: 3.minutes)
    assert_equal 1, @person.attention_spans.count
    assert_equal 60, @person.attention_spans.first.seconds
  end

  test "a gap longer than the idle limit starts a new span" do
    AttentionSpan.record_heartbeat!(person: @person, activity: "review", work_item: @item, at: @t, idle_gap: 3.minutes)
    AttentionSpan.record_heartbeat!(person: @person, activity: "review", work_item: @item, at: @t + 600, idle_gap: 3.minutes)
    assert_equal 2, @person.attention_spans.count
  end

  test "switching ticket or activity starts a new span" do
    AttentionSpan.record_heartbeat!(person: @person, activity: "review", work_item: @item, at: @t, idle_gap: 3.minutes)
    AttentionSpan.record_heartbeat!(person: @person, activity: "qa", work_item: @item, at: @t + 30, idle_gap: 3.minutes)
    assert_equal 2, @person.attention_spans.count
  end
end
