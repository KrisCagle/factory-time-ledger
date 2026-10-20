require "test_helper"

class ApiTest < ActionDispatch::IntegrationTest
  test "posts an event and a heartbeat, then drafts appear" do
    post "/api/v1/events", params: event_payload.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :created
    assert_equal 1, response.parsed_body["accepted"]

    now = Time.current.change(hour: 10)
    post "/api/v1/attention", params: { person_email: "dev@example.com", activity: "review", jira_key: "TEST-1", at: now.iso8601 }.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :ok
    post "/api/v1/attention", params: { person_email: "dev@example.com", activity: "review", jira_key: "TEST-1", at: (now + 120).iso8601 }.to_json, headers: { "Content-Type" => "application/json" }

    person = Person.find_by!(email: "dev@example.com")
    drafts = DayAttribution.new(person:, date: now.to_date).write_drafts!
    assert_equal 1, drafts.count
    assert_equal 120, drafts.first.direct_seconds
  end

  test "pages render" do
    EventIngest.call(event_payload)
    item = WorkItem.first
    %W[/ /batches /batches/#{item.batch_id} /tickets /tickets/#{item.id} /harvest /settings].each do |path|
      get path
      assert_response :success, "#{path} did not render"
    end
  end
end
