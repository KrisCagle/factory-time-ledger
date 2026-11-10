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

  test "settings shows Scarif setup steps when no token is set" do
    get "/settings"
    assert_response :success
    assert_match "Scarif connection", response.body
    assert_match "work_item:read", response.body
  end

  test "Scarif buttons explain a missing token" do
    post "/scarif_connection/sync"
    assert_redirected_to settings_path(anchor: "scarif")
    assert_match "SCARIF_API_TOKEN", flash[:alert]
  end

  test "Scarif settings save" do
    ExternalRecord.create!(source: "scarif", external_id: "skipped-1")
    patch "/scarif_connection", params: { ledger_setting: { scarif_only_mine: "0", scarif_lookback_days: "30" } }
    assert_equal 0, ExternalRecord.count, "skipped items are re-decided after a settings change"
    assert_redirected_to settings_path(anchor: "scarif")
    setting = LedgerSetting.current
    assert_equal false, setting.scarif_only_mine
    assert_equal 30, setting.scarif_lookback_days
  end

  test "settings renders with a Scarif token configured" do
    ENV["SCARIF_API_TOKEN"] = "test-token"
    LedgerSetting.current.update!(scarif_user_name: "Kris Cagle", scarif_token_scopes: ["work_item:read", "work_item:write"],
                                  scarif_checked_at: Time.current, scarif_last_synced_at: Time.current,
                                  scarif_last_sync_summary: "Read 2 recently changed Scarif items")
    get "/settings"
    assert_response :success
    assert_match "Kris Cagle", response.body
    assert_match "can also change things in Scarif", response.body
  ensure
    ENV.delete("SCARIF_API_TOKEN")
  end

  # --- Foreman sign-in ---------------------------------------------------------------

  test "sign in sends you to Foreman's approval page and remembers the attempt" do
    post "/foreman_connection/sign_in"
    assert_response :redirect
    url = URI(response.location)
    assert_equal "/cli-auth/authorize", url.path
    query = URI.decode_www_form(url.query).to_h
    setting = LedgerSetting.current
    assert_equal setting.foreman_pending_state, query["state"]
    assert_equal ForemanApi::Client.challenge_for(setting.foreman_pending_verifier), query["challenge"]
    assert_equal "80", query["port"] # integration tests run on port 80
  end

  test "a callback that doesn't match the sign-in started here is refused" do
    LedgerSetting.current.update!(foreman_pending_state: "expected", foreman_pending_verifier: "v")
    get "/callback", params: { code: "c", state: "someone-else" }
    assert_redirected_to settings_path(anchor: "foreman")
    assert_match "didn't match", flash[:alert]
    assert_nil LedgerSetting.current.foreman_token
  end

  test "a matching callback trades the code for a token" do
    LedgerSetting.current.update!(foreman_pending_state: "st", foreman_pending_verifier: "ver")
    original = ForemanApi::Client.instance_method(:exchange)
    received = nil
    ForemanApi::Client.define_method(:exchange) do |code:, verifier:|
      received = [code, verifier]
      { "id" => 7, "token" => "tok", "expiresAt" => 12.hours.from_now.iso8601, "email" => "kris@example.com",
        "name" => "Kris Cagle", "surface" => "all", "scopes" => [] }
    end
    get "/callback", params: { code: "the-code", state: "st" }
    assert_equal %w[the-code ver], received
    setting = LedgerSetting.current
    assert_equal "tok", setting.foreman_token
    assert_nil setting.foreman_pending_verifier
    assert ForemanApi.signed_in?(setting)
    assert_match "Signed in to Foreman as Kris Cagle", flash[:notice]
  ensure
    ForemanApi::Client.define_method(:exchange, original)
  end

  test "settings and ticket pages render with Foreman data" do
    EventIngest.call(event_payload)
    item = WorkItem.first
    LedgerSetting.current.update!(foreman_token: "tok", foreman_token_expires_at: 2.hours.from_now, foreman_email: "kris@example.com")
    ForemanRun.create!(work_item: item, followed: true, workflow: "deliver-story", position: "review", state: "working",
                       fetched_at: Time.current, tasks: [FakeForemanClient.task("implement", 3.hours.ago, claimed: 2.hours.ago, left: 1.hour.ago)],
                       timeline: [{ "at" => 1.hour.ago.iso8601, "summary" => "Approved", "actor" => { "name" => "Ron" } }])
    get "/settings"
    assert_response :success
    assert_match "Foreman connection", response.body
    assert_match "Refresh from Foreman", response.body
    get "/tickets/#{item.id}"
    assert_response :success
    assert_match "Process in Foreman", response.body
    assert_match "Approved", response.body
  end

  test "sign out forgets the token" do
    LedgerSetting.current.update!(foreman_token: "tok", foreman_token_expires_at: 2.hours.from_now)
    delete "/foreman_connection/sign_out"
    assert_nil LedgerSetting.current.foreman_token
  end
end

