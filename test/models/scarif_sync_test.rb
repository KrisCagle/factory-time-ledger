require "test_helper"

class ScarifSyncTest < ActiveSupport::TestCase
  T = Time.zone.parse("2026-10-28 09:00")

  setup do
    @client = FakeScarifClient.new
    @setting = LedgerSetting.current
    @now = T + 8.hours
    ENV["SCARIF_API_TOKEN"] = "test-token"
  end

  teardown { ENV.delete("SCARIF_API_TOKEN") }

  def sync(now: @now) = Scarif::Sync.call(client: @client, setting: @setting.reload, now:)

  # Two factory tickets Kris enqueued 3 minutes apart, one review approved, one sent back.
  def build_kris_batch
    @client.add_item(id: "a1", jira_key: "ACME-1", created_at: T, updated_at: T + 3.hours, status: "done", points: 2, total_cost: 3.5)
    @client.add_node_run("a1", id: "n1", node_id: "plan", started_at: T + 2.minutes, completed_at: T + 10.minutes, cost: 0.5)
    @client.add_node_run("a1", id: "n2", node_id: "implement", started_at: T + 11.minutes, completed_at: T + 61.minutes, cost: 3.0)
    @client.add_ask("a1", id: "q1", jira_key: "ACME-1", kind: "merge_ready", opened_at: T + 70.minutes,
                          answered_at: T + 2.hours, resolution: "approve", answered_by: "kris@example.com")

    @client.add_item(id: "a2", jira_key: "ACME-2", created_at: T + 3.minutes, updated_at: T + 4.hours, status: "human_review",
                     points: 5, total_cost: 6.0, open_ask: { "id" => "q3", "kind" => "merge_ready" })
    @client.add_node_run("a2", id: "n3", node_id: "implement", started_at: T + 5.minutes, completed_at: T + 95.minutes, cost: 4.0)
    @client.add_node_run("a2", id: "n4", node_id: "rework", started_at: T + 3.hours, completed_at: nil)
    @client.add_ask("a2", id: "q2", jira_key: "ACME-2", kind: "merge_ready", opened_at: T + 100.minutes,
                          answered_at: T + 2.hours, resolution: "revise", answered_by: "kris@example.com")
    @client.add_ask("a2", id: "q3", jira_key: "ACME-2", kind: "merge_ready", opened_at: T + 4.hours)
  end

  test "connection check records the token owner and scopes" do
    outcome = Scarif::CheckConnection.call(client: @client, setting: @setting)
    assert outcome.ok, outcome.message
    assert_equal "11", @setting.reload.scarif_user_id
    assert_equal "kris@example.com", @setting.scarif_user_email
    assert_equal ["work_item:read"], @setting.scarif_token_scopes
  end

  test "connection check warns about tokens that can write" do
    @client.me_body["token"]["scopes"] = ["work_item:read", "work_item:write"]
    outcome = Scarif::CheckConnection.call(client: @client, setting: @setting)
    assert outcome.ok
    assert_match "safer", outcome.message
  end

  test "connection check refuses a token without work_item:read" do
    @client.me_body["token"]["scopes"] = ["repo:read"]
    refute Scarif::CheckConnection.call(client: @client, setting: @setting).ok
  end

  test "connection check refuses a service-account token" do
    @client.me_body = { "principal" => { "kind" => "service_account" }, "token" => { "scopes" => ["work_item:read"] } }
    outcome = Scarif::CheckConnection.call(client: @client, setting: @setting)
    refute outcome.ok
    assert_match "service account", outcome.message
  end

  test "sync turns Scarif work items into tickets with agent runs, cost, asks, and status" do
    build_kris_batch
    outcome = sync
    assert outcome.ok, outcome.message
    assert_equal 2, outcome.counts[:updated]

    one = WorkItem.find_by!(jira_key: "ACME-1")
    assert_equal "scarif", one.source
    assert_equal "Summary of ACME-1", one.summary
    assert_equal "twinsunllc/acme-portal", one.project.repo
    assert_equal 2, one.agent_points
    assert_equal "done", one.status
    assert_equal 2, one.agent_runs.count
    assert_equal 58 * 60, one.agent_seconds
    assert_equal BigDecimal("3.5"), one.agent_cost_usd
    types = one.pipeline_events.map(&:event_type)
    %w[pipeline_started stage_claimed stage_completed wait_human_entered wait_human_resolved human_review_approved pipeline_completed].each do |t|
      assert_includes types, t
    end
    assert_equal "kris@example.com", one.pipeline_events.find_by(event_type: "human_review_approved").person.email

    two = WorkItem.find_by!(jira_key: "ACME-2")
    assert_equal "waiting_on_human", two.status, "an open ask means it's waiting on you"
    assert_equal 1, two.rework_count, "a revise answer counts as rework"
    assert_nil two.agent_runs.find_by(external_id: "node-n4").completed_at, "a running node has no end yet"
  end

  test "agent cost matches Scarif's total even when not every dollar is itemized" do
    build_kris_batch
    sync
    two = WorkItem.find_by!(jira_key: "ACME-2")
    assert_equal BigDecimal("6.0"), two.agent_cost_usd
    adjustment = two.agent_runs.find_by!(external_id: "wi-a2-unitemized")
    assert_equal BigDecimal("2.0"), adjustment.cost_usd
    assert_equal 0, adjustment.seconds
  end

  test "tickets enqueued close together become one batch" do
    build_kris_batch
    sync
    batch = WorkItem.find_by!(jira_key: "ACME-1").batch
    assert batch
    assert_equal batch, WorkItem.find_by!(jira_key: "ACME-2").batch
    assert_equal "scarif", batch.source
    assert_match "(2 tickets)", batch.label
  end

  test "a lone ticket is not a batch" do
    @client.add_item(id: "solo", jira_key: "ACME-9", created_at: T)
    @client.add_item(id: "later", jira_key: "ACME-10", created_at: T + 1.hour)
    sync
    assert_nil WorkItem.find_by!(jira_key: "ACME-9").batch
    assert_equal 0, Batch.count
  end

  test "work items enqueued by someone else are skipped unless asked for" do
    @client.add_item(id: "x1", jira_key: "OTHER-1", created_at: T, orderer: FakeScarifClient::OTHER_ID)
    outcome = sync
    assert_equal 1, outcome.counts[:not_mine]
    assert_nil WorkItem.find_by(jira_key: "OTHER-1")

    @setting.update!(scarif_only_mine: false, scarif_last_synced_at: nil)
    sync
    assert WorkItem.find_by(jira_key: "OTHER-1")
  end

  test "re-syncing unchanged data reads nothing new and duplicates nothing" do
    build_kris_batch
    sync
    events = PipelineEvent.count
    runs = AgentRun.count
    @client.calls.clear

    @client.touch("a2", @now + 1.minute) # inside the overlap window, but nothing else changed
    @client.details["a2"]["updated_at"] = @client.items.find { |i| i["id"] == "a2" }["updated_at"]
    record = ExternalRecord.find_by!(external_id: "a2")
    record.update!(external_updated_at: Time.zone.parse(@client.items.find { |i| i["id"] == "a2" }["updated_at"]))

    outcome = sync(now: @now + 5.minutes)
    assert_equal 0, outcome.counts[:updated].to_i
    assert_equal 1, outcome.counts[:unchanged]
    assert_equal events, PipelineEvent.count
    assert_equal runs, AgentRun.count
    assert_empty @client.calls.select { |c| c.first == :work_item }, "unchanged items aren't re-read"
  end

  test "a changed item picks up new runs and its new status" do
    build_kris_batch
    sync
    run = @client.node_runs_by_id["a2"].find { |r| r["id"] == "n4" }
    run["completed_at"] = (T + 5.hours).iso8601(3)
    run["cost_usd"] = 1.25
    @client.items.find { |i| i["id"] == "a2" }.merge!("status" => "done", "open_factory_ask" => nil, "total_cost_usd" => 7.25)
    @client.details["a2"]["status"] = "done"
    @client.touch("a2", @now + 30.minutes)

    outcome = sync(now: @now + 1.hour)
    assert_equal 1, outcome.counts[:updated]
    two = WorkItem.find_by!(jira_key: "ACME-2")
    assert_equal "done", two.status
    assert_equal BigDecimal("1.25"), two.agent_runs.find_by!(external_id: "node-n4").cost_usd
    assert_equal BigDecimal("7.25"), two.agent_cost_usd
  end

  test "older items without a factory job use stages for timing" do
    stages = [{ "id" => "s1", "stage_type" => "implement", "sequence" => 1, "status" => "completed",
                "started_at" => (T + 1.minute).iso8601(3), "completed_at" => (T + 31.minutes).iso8601(3) }]
    @client.add_item(id: "old", jira_key: "OLD-1", created_at: T, factory: false, total_cost: 1.0, stages:)
    sync
    item = WorkItem.find_by!(jira_key: "OLD-1")
    assert_equal 30 * 60, item.agent_runs.find_by!(external_id: "stage-s1").seconds
    assert_equal BigDecimal("1.0"), item.agent_cost_usd
    assert_empty @client.calls.select { |c| c.first == :node_runs }
  end

  test "paging stops at items older than the lookback window" do
    @client.page_size = 2
    5.times { |i| @client.add_item(id: "r#{i}", jira_key: "NEW-#{i}", created_at: @now - i.hours) }
    @client.add_item(id: "stale", jira_key: "STALE-1", created_at: @now - 30.days)
    sync
    assert_nil WorkItem.find_by(jira_key: "STALE-1")
    assert_equal 5, WorkItem.where("jira_key LIKE 'NEW-%'").count
  end

  test "sync needs a token" do
    ENV.delete("SCARIF_API_TOKEN")
    outcome = sync
    refute outcome.ok
    assert_match "SCARIF_API_TOKEN", outcome.message
  end

  test "a Scarif error stops the sync and is recorded" do
    def @client.work_items(**) = raise(Scarif::Client::Error.new("Scarif rejected the token (401).", status: 401))
    Scarif::CheckConnection.call(client: @client, setting: @setting)
    outcome = sync
    refute outcome.ok
    assert_match "401", @setting.reload.scarif_sync_error
  end
end
