require "test_helper"

# Exercises the Harvest services against a fake client, so no network or
# Harvest account is needed.
class HarvestIntegrationTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :posted
    attr_accessor :timestamp_mode, :fail_with

    def initialize(live: true)
      @live = live
      @posted = []
      @timestamp_mode = false
    end

    def dry_run? = !@live

    def company = { "name" => "Twin Sun", "wants_timestamp_timers" => timestamp_mode }
    def me = { "id" => 555, "first_name" => "Dev", "last_name" => "Person", "email" => "dev@example.com" }

    def project_assignments
      [{
        "is_active" => true,
        "project" => { "id" => 900, "name" => "Acme Portal", "code" => "ACME" },
        "client" => { "name" => "Acme" },
        "task_assignments" => [
          { "is_active" => true, "billable" => true, "task" => { "id" => 1, "name" => "Development" } },
          { "is_active" => true, "billable" => true, "task" => { "id" => 2, "name" => "QA / Review" } },
          { "is_active" => true, "billable" => false, "task" => { "id" => 3, "name" => "Project Management" } },
          { "is_active" => false, "billable" => true, "task" => { "id" => 4, "name" => "Retired task" } }
        ]
      }]
    end

    def create_time_entry(payload)
      raise "fake error" if fail_with
      return Harvest::Client::Response.new(ok: true, dry_run: true, payload:) unless @live

      @posted << payload
      Harvest::Client::Response.new(ok: true, dry_run: false, entry_id: 7777, payload:)
    end
  end

  setup do
    EventIngest.call(event_payload)
    @person = Person.for_email!("dev@example.com")
    @item = WorkItem.find_by!(jira_key: "TEST-1")
    @item.project.update!(harvest_project_id: 900, harvest_dev_task_id: 1, harvest_qa_task_id: 2, harvest_supervision_task_id: 3)
    @draft = TimeDraft.create!(person: @person, work_item: @item, spent_on: Date.current, activity: "review",
                               direct_seconds: 1800, overhead_seconds: 0, hours: 0.5, notes: "TEST-1", status: "approved")
    @client = FakeClient.new
  end

  test "check connection records the account and fills in the person's Harvest user ID" do
    outcome = Harvest::CheckConnection.call(client: @client)
    assert outcome.ok
    setting = LedgerSetting.current
    assert_equal "Twin Sun", setting.harvest_account_name
    assert_equal false, setting.harvest_timestamp_mode
    assert_equal 555, @person.reload.harvest_user_id
  end

  test "sync loads projects with only their active tasks" do
    outcome = Harvest::SyncProjects.call(client: @client)
    assert outcome.ok
    project = HarvestProject.find_by!(harvest_id: 900)
    assert_equal [1, 2, 3], project.task_ids.sort
    assert_equal "Acme — Acme Portal", project.label
  end

  test "live send is blocked until connection is checked and projects are loaded" do
    outcome = Harvest::SendDraft.call(@draft, client: @client)
    refute outcome.ok
    assert_match "Test connection", outcome.message
    assert_empty @client.posted
  end

  test "live send succeeds once connected and the project and task are real" do
    Harvest::CheckConnection.call(client: @client)
    Harvest::SyncProjects.call(client: @client)

    outcome = Harvest::SendDraft.call(@draft, client: @client)
    assert outcome.ok, outcome.message
    assert_equal "sent", @draft.reload.status
    assert_equal 7777, @draft.harvest_time_entry_id
    payload = @client.posted.first
    assert_equal 900, payload[:project_id]
    assert_equal 2, payload[:task_id]
    refute payload.key?(:user_id), "entries for the token owner shouldn't carry user_id"
  end

  test "live send refuses a project that isn't in the user's Harvest" do
    Harvest::CheckConnection.call(client: @client)
    Harvest::SyncProjects.call(client: @client)
    @item.project.update!(harvest_project_id: 11_111_111)

    outcome = Harvest::SendDraft.call(@draft, client: @client)
    refute outcome.ok
    assert_match "isn't one of your Harvest projects", outcome.message
    assert_empty @client.posted
  end

  test "live send refuses a task not assigned to the project" do
    Harvest::CheckConnection.call(client: @client)
    Harvest::SyncProjects.call(client: @client)
    @item.project.update!(harvest_qa_task_id: 4)

    outcome = Harvest::SendDraft.call(@draft, client: @client)
    refute outcome.ok
    assert_match "isn't assigned", outcome.message
  end

  test "live send refuses timestamp-mode accounts" do
    @client.timestamp_mode = true
    refute Harvest::CheckConnection.call(client: @client).ok
    Harvest::SyncProjects.call(client: @client)

    outcome = Harvest::SendDraft.call(@draft, client: @client)
    refute outcome.ok
    assert_match "start and end times", outcome.message
  end

  test "dry run keeps the draft approved and stores the payload" do
    outcome = Harvest::SendDraft.call(@draft, client: FakeClient.new(live: false))
    assert outcome.dry_run
    assert_equal "approved", @draft.reload.status
    assert_equal 900, @draft.last_payload["project_id"]
  end
end
