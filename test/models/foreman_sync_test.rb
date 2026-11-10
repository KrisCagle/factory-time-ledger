require "test_helper"

class ForemanSyncTest < ActiveSupport::TestCase
  T = Time.zone.parse("2026-11-09 09:00")

  setup do
    @client = FakeForemanClient.new
    @setting = LedgerSetting.current
    @setting.update!(foreman_token: "tok", foreman_token_expires_at: 1.hour.from_now, foreman_email: "kris@example.com", harvest_user_id: 555)
    EventIngest.call(event_payload("jira_key" => "ACME-1"))
    EventIngest.call(event_payload("jira_key" => "ACME-2"))
  end

  def sync = ForemanApi::Sync.call(client: @client, setting: @setting.reload, now: T + 1.day)
  def task(...) = FakeForemanClient.task(...)

  test "stores the inferred run and works out waiting vs working time per step" do
    @client.add_run("ACME-1", tasks: [
      task("implement", T, claimed: T + 2.hours, left: T + 5.hours, implementor: "555", source: "harvest", outcome: "done"),
      task("review", T + 5.hours, claimed: T + 6.hours, left: nil, implementor: "abc-jira-id")
    ], position: "review")
    outcome = sync
    assert outcome.ok, outcome.message

    run = WorkItem.find_by!(jira_key: "ACME-1").foreman_run
    assert run.followed
    assert_equal "deliver-story", run.workflow
    assert_equal "review", run.position
    assert_equal "being worked on", run.state_label

    implement, review = run.steps
    assert_equal 2.hours.to_i, implement.wait_seconds
    assert_equal 3.hours.to_i, implement.work_seconds
    assert implement.mine?(555), "Harvest user id matches you"
    refute review.mine?(555)
    assert review.open?
    assert_equal 1.hour.to_i, review.wait_seconds
    assert_equal 3.hours.to_i, run.total_wait_seconds
  end

  test "a step never claimed counts only as waiting" do
    step = ForemanRun::Step.new(task("qa", T, left: T + 4.hours))
    assert_equal 4.hours.to_i, step.wait_seconds
    assert_equal 0, step.work_seconds
  end

  test "tickets Foreman doesn't follow are marked, not errors" do
    @client.add_run("ACME-1", tasks: [])
    outcome = sync
    assert_equal 1, outcome.counts[:followed]
    assert_equal 1, outcome.counts[:not_followed]
    refute WorkItem.find_by!(jira_key: "ACME-2").foreman_run.followed
  end

  test "keeps the engine timeline when there is one" do
    @client.add_run("ACME-1", tasks: [])
    @client.timelines["ACME-1"] = { "story" => { "key" => "ACME-1" }, "runs" => [],
                                    "entries" => [{ "at" => T.iso8601, "kind" => "approval", "summary" => "Approved", "actor" => "ron@example.com" }] }
    sync
    assert_equal "Approved", WorkItem.find_by!(jira_key: "ACME-1").foreman_run.timeline.first["summary"]
  end

  test "without a granted scope it skips timelines once and says why" do
    @client.add_run("ACME-1", tasks: [])
    @client.add_run("ACME-2", tasks: [])
    @client.timeline_status = 403
    outcome = sync
    assert outcome.ok
    assert_match "granted scope", outcome.message
    assert_equal 1, @client.calls.count { |c| c.first == :story_timeline }, "asks for timelines once, then stops"
    assert_equal 2, ForemanRun.where(followed: true).count
  end

  test "an expired or rejected sign-in stops the refresh and is recorded" do
    @client.run_status = 401
    outcome = sync
    refute outcome.ok
    assert_match "401", @setting.reload.foreman_sync_error
  end

  test "does nothing while signed out" do
    @setting.update!(foreman_token_expires_at: 1.minute.ago)
    outcome = sync
    refute outcome.ok
    assert_match "Sign in", outcome.message
    assert_empty @client.calls
  end

  test "only asks about Jira-style keys" do
    EventIngest.call(event_payload("jira_key" => "WI-abc", "batch_id" => nil))
    sync
    refute @client.calls.any? { |c| c[1] == "WI-ABC" }
  end
end
