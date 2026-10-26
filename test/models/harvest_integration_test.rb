require "test_helper"

# Exercises the Harvest services against FakeHarvestClient, so no network or
# Harvest account is needed.
class HarvestIntegrationTest < ActiveSupport::TestCase
  setup do
    EventIngest.call(event_payload)
    @person = Person.for_email!("dev@example.com")
    @item = WorkItem.find_by!(jira_key: "TEST-1")
    @project = @item.project
    @project.update!(harvest_project_id: 900, harvest_dev_task_id: 1, harvest_qa_task_id: 2, harvest_supervision_task_id: 3)
    @draft = TimeDraft.create!(person: @person, work_item: @item, spent_on: Date.current, activity: "review",
                               direct_seconds: 1800, overhead_seconds: 0, hours: 0.5, notes: "TEST-1", status: "approved")
    @client = FakeHarvestClient.new
  end

  def go_live!
    Harvest::CheckConnection.call(client: @client)
    Harvest::SyncProjects.call(client: @client)
  end

  # --- Connection and projects ---------------------------------------------

  test "check connection records the account and fills in the person's Harvest user ID" do
    outcome = Harvest::CheckConnection.call(client: @client)
    assert outcome.ok
    setting = LedgerSetting.current
    assert_equal "Twin Sun", setting.harvest_account_name
    assert_equal false, setting.harvest_timestamp_mode
    assert_equal 555, @person.reload.harvest_user_id
    assert_equal @person, outcome.person
  end

  test "check connection adds the token owner as a person if they're missing" do
    @draft.destroy
    Batch.update_all(started_by_id: nil)
    PipelineEvent.update_all(person_id: nil)
    @person.destroy
    outcome = Harvest::CheckConnection.call(client: @client)
    assert outcome.ok
    created = Person.find_by!(email: "dev@example.com")
    assert_equal "Dev Person", created.name
    assert_equal 555, created.harvest_user_id
  end

  test "sync loads projects with only their active tasks" do
    outcome = Harvest::SyncProjects.call(client: @client)
    assert outcome.ok
    project = HarvestProject.find_by!(harvest_id: 900)
    assert_equal [1, 2, 3], project.task_ids.sort
    assert_equal "Acme — Acme Portal", project.label
  end

  # --- Sending ---------------------------------------------------------------

  test "live send is blocked until connection is checked and projects are loaded" do
    outcome = Harvest::SendDraft.call(@draft, client: @client)
    refute outcome.ok
    assert_match "Test connection", outcome.message
    assert_empty @client.posted
  end

  test "live send succeeds, then reads the entry back and marks it verified" do
    go_live!
    outcome = Harvest::SendDraft.call(@draft, client: @client)
    assert outcome.ok, outcome.message
    assert_match "Sent and verified", outcome.message

    @draft.reload
    assert_equal "sent", @draft.status
    assert @draft.harvest_time_entry_id
    assert @draft.harvest_verified_at
    payload = @client.posted.first
    assert_equal 900, payload[:project_id]
    assert_equal 2, payload[:task_id]
    refute payload.key?(:user_id), "entries for the token owner shouldn't carry user_id"
  end

  test "live send refuses a project that isn't in the user's Harvest" do
    go_live!
    @project.update!(harvest_project_id: 11_111_111)
    outcome = Harvest::SendDraft.call(@draft, client: @client)
    refute outcome.ok
    assert_match "isn't one of your Harvest projects", outcome.message
    assert_empty @client.posted
  end

  test "live send refuses a task not assigned to the project" do
    go_live!
    @project.update!(harvest_qa_task_id: 4)
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

  test "a send Harvest rejects marks the draft failed" do
    go_live!
    @client.refuse_create = "Harvest 422: Project is archived"
    outcome = Harvest::SendDraft.call(@draft, client: @client)
    refute outcome.ok
    assert_equal "failed", @draft.reload.status
    assert_match "archived", @draft.last_error
  end

  test "dry run keeps the draft approved and stores the payload" do
    outcome = Harvest::SendDraft.call(@draft, client: FakeHarvestClient.new(live: false))
    assert outcome.dry_run
    assert_equal "approved", @draft.reload.status
    assert_equal 900, @draft.last_payload["project_id"]
  end

  # --- Verify and undo ---------------------------------------------------------

  test "verify notices an entry that was edited in Harvest" do
    go_live!
    Harvest::SendDraft.call(@draft, client: @client)
    @client.entries[@draft.reload.harvest_time_entry_id]["hours"] = 2.0

    outcome = Harvest::VerifyEntry.call(@draft, client: @client)
    refute outcome.ok
    assert_nil @draft.reload.harvest_verified_at
    assert_match "hours", @draft.harvest_verify_note
  end

  test "verify notices an entry deleted in Harvest" do
    go_live!
    Harvest::SendDraft.call(@draft, client: @client)
    @client.entries.clear

    outcome = Harvest::VerifyEntry.call(@draft.reload, client: @client)
    refute outcome.ok
    assert_match "no longer exists", @draft.reload.harvest_verify_note
  end

  test "undo deletes the entry from Harvest and puts the draft back to approved" do
    go_live!
    Harvest::SendDraft.call(@draft, client: @client)
    entry_id = @draft.reload.harvest_time_entry_id

    outcome = Harvest::UndoDraft.call(@draft, client: @client)
    assert outcome.ok, outcome.message
    refute @client.entries.key?(entry_id)
    @draft.reload
    assert_equal "approved", @draft.status
    assert_nil @draft.harvest_time_entry_id
    assert_nil @draft.harvest_verified_at
  end

  test "undo still succeeds if the entry was already deleted in Harvest" do
    go_live!
    Harvest::SendDraft.call(@draft, client: @client)
    @client.entries.clear

    assert Harvest::UndoDraft.call(@draft.reload, client: @client).ok
    assert_equal "approved", @draft.reload.status
  end

  test "undo that Harvest refuses leaves the draft sent" do
    go_live!
    Harvest::SendDraft.call(@draft, client: @client)
    @client.refuse_delete = "Entry is in a locked timesheet"

    outcome = Harvest::UndoDraft.call(@draft.reload, client: @client)
    refute outcome.ok
    assert_equal "sent", @draft.reload.status
    assert_match "locked", @draft.last_error
  end

  # --- Test entry ----------------------------------------------------------------

  test "test entry creates, verifies, deletes, and leaves nothing behind" do
    go_live!
    outcome = Harvest::TestEntry.call(project: @project, client: @client)
    assert outcome.ok, outcome.message
    assert_equal 4, outcome.steps.size
    assert outcome.steps.all?(&:ok)
    assert_empty @client.entries
    assert_equal 1, @client.posted.first[:task_id]
    assert_in_delta 0.01, @client.posted.first[:hours]

    setting = LedgerSetting.current.reload
    assert setting.harvest_test_passed_at
    assert_equal 4, setting.harvest_test_log.size
  end

  test "test entry that can't be deleted says which entry to remove by hand" do
    go_live!
    @client.refuse_delete = "Entry is in a locked timesheet"
    outcome = Harvest::TestEntry.call(project: @project, client: @client)
    refute outcome.ok
    assert_match(/#\d+ was created but couldn't be deleted/, outcome.message)
    assert_nil LedgerSetting.current.reload.harvest_test_passed_at
  end

  test "test entry is refused before the connection is checked" do
    outcome = Harvest::TestEntry.call(project: @project, client: @client)
    refute outcome.ok
    assert_match "Test connection", outcome.message
    assert_empty @client.posted
  end

  test "test entry does nothing in dry run" do
    outcome = Harvest::TestEntry.call(project: @project, client: FakeHarvestClient.new(live: false))
    refute outcome.ok
    assert_match "isn't connected", outcome.message
  end

  # --- Go-live checklist ------------------------------------------------------------

  test "checklist tracks the milestone steps" do
    checklist = -> { GoLiveChecklist.new(setting: LedgerSetting.current.reload) }
    assert_equal 0, checklist.call.steps.drop(1).count(&:done)

    go_live!
    steps = checklist.call.steps
    assert steps[1].done, "connection tested"
    assert steps[2].done, "projects loaded"
    assert steps[3].done, "project mapped to real Harvest IDs"
    refute steps[4].done

    Harvest::TestEntry.call(project: @project, client: @client)
    assert checklist.call.steps[4].done

    Harvest::SendDraft.call(@draft, client: @client)
    assert checklist.call.steps[5].done
  end
end
