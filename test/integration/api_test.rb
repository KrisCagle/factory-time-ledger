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

  test "settings renders with demo data, the checklist, and Harvest not connected" do
    DemoData.load!
    get "/settings"
    assert_response :success
    assert_match "Going live", response.body
    assert_match "Remove demo data", response.body
  end

  test "harvest drafts page renders sent, verified drafts" do
    EventIngest.call(event_payload)
    person = Person.find_by!(email: "dev@example.com")
    TimeDraft.create!(person:, work_item: WorkItem.first, spent_on: Date.current, activity: "review", hours: 0.5,
                      status: "sent", harvest_time_entry_id: 123, harvest_verified_at: Time.current, last_payload: { project_id: 1 })
    get "/harvest", params: { person_id: person.id }
    assert_response :success
    assert_match "verified in Harvest", response.body
    assert_match "Undo", response.body
  end

  test "adding a ticket by hand" do
    Person.for_email!("kris@example.com")
    post "/tickets", params: { work_item: { jira_key: "acme-9", summary: "Manual work", repo: "twinsunllc/acme" } }
    item = WorkItem.find_by!(jira_key: "ACME-9")
    assert_redirected_to work_item_path(item)
    assert_equal "Manual work", item.summary
    assert_equal "twinsunllc/acme", item.project.repo
    assert_equal "ticket_added", item.pipeline_events.last.event_type
  end

  test "adding a ticket needs a key and a project" do
    post "/tickets", params: { work_item: { jira_key: "", repo: "" } }
    assert_redirected_to work_items_path
    assert_equal 0, WorkItem.count
  end

  test "removing demo data from settings" do
    DemoData.load!
    delete "/demo_data"
    assert_redirected_to settings_path
    refute DemoData.present?
  end

  test "test entry without Harvest connected explains why" do
    EventIngest.call(event_payload)
    post "/harvest_connection/test_entry", params: { project_id: Project.first.id }
    assert_redirected_to settings_path(anchor: "harvest")
    assert_match "isn't connected", flash[:alert]
  end

  test "verify and undo routes respond for a person's own draft" do
    EventIngest.call(event_payload)
    person = Person.find_by!(email: "dev@example.com")
    draft = TimeDraft.create!(person:, work_item: WorkItem.first, spent_on: Date.current, activity: "review", hours: 0.5,
                              status: "sent", harvest_time_entry_id: 123, last_payload: { project_id: 1 })
    get "/settings", params: { person_id: person.id } # pick the person for this session
    post "/harvest/#{draft.id}/verify"
    assert_response :redirect
    post "/harvest/#{draft.id}/undo"
    assert_response :redirect
    assert_equal "sent", draft.reload.status, "nothing changes without a Harvest connection"
  end
end
