require "test_helper"

class EventIngestTest < ActiveSupport::TestCase
  test "creates the ticket, batch, project and person from the first event" do
    EventIngest.call(event_payload)
    item = WorkItem.find_by!(jira_key: "TEST-1")
    assert_equal "acme/app", item.project.repo
    assert_equal "b1", item.batch.external_id
    assert_equal 2, item.agent_points
    assert_equal "in_progress", item.status
    assert_equal "dev@example.com", item.batch.started_by.email
  end

  test "re-sending the same event is a no-op" do
    payload = event_payload
    EventIngest.call(payload)
    result = EventIngest.call(payload)
    assert result.duplicate
    assert_equal 1, PipelineEvent.count
  end

  test "stage events build agent runs with cost" do
    t = Time.current
    EventIngest.call(event_payload("event_type" => "stage_claimed", "occurred_at" => t.iso8601, "data" => { "stage_id" => "s1", "stage_type" => "implement" }))
    EventIngest.call(event_payload("event_type" => "stage_completed", "occurred_at" => (t + 600).iso8601, "data" => { "stage_id" => "s1", "cost_usd" => "1.25" }))
    run = AgentRun.find_by!(external_id: "s1")
    assert_equal 600, run.seconds
    assert_equal BigDecimal("1.25"), run.cost_usd
  end

  test "rejects events missing required fields" do
    assert_raises(EventIngest::Invalid) { EventIngest.call(event_payload("jira_key" => nil)) }
  end
end
