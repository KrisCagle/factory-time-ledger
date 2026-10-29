# Stands in for Scarif::Client in tests. Responses follow scarif-web's
# blueprints: WorkItemBlueprint (summary + detailed views), StageBlueprint,
# FactoryNodeRunBlueprint, FactoryAskBlueprint and API::V2::MeController.
class FakeScarifClient
  ME_ID = "11".freeze
  OTHER_ID = "22".freeze

  attr_accessor :me_body, :items, :details, :node_runs_by_id, :asks, :page_size
  attr_reader :calls

  def initialize
    @calls = []
    @page_size = 100
    @me_body = {
      "user" => { "id" => ME_ID, "email" => "kris@example.com", "name" => "Kris Cagle" },
      "token" => { "id" => "t1", "name" => "time ledger", "prefix" => "scarif_", "scopes" => ["work_item:read"], "expires_at" => nil }
    }
    @items = []
    @details = {}
    @node_runs_by_id = {}
    @asks = []
  end

  # --- builders ----------------------------------------------------------------

  def add_item(id:, jira_key:, created_at:, updated_at: created_at, status: "in_progress", orderer: ME_ID, summary: nil,
               points: nil, total_cost: nil, repo: "twinsunllc/acme-portal", factory: true, open_ask: nil, stages: nil)
    item = {
      "id" => id, "jira_key" => jira_key, "jira_summary" => summary || "Summary of #{jira_key}", "status" => status,
      "display_key" => "WI-#{id}", "created_at" => created_at.iso8601(3), "updated_at" => updated_at.iso8601(3),
      "agent_points_size" => points, "agent_points" => points && { "size" => points },
      "enqueued_by" => orderer && { "id" => orderer, "name" => orderer == ME_ID ? "Kris Cagle" : "Someone Else" },
      "enqueued_via" => "CLI", "repositories" => [{ "id" => 1, "name" => repo.split("/").last, "full_name" => repo }],
      "total_cost_usd" => total_cost, "infra_cost_usd" => 0.0, "current_stage" => nil, "waiting_on" => []
    }
    item["factory_job"] = { "workflow" => "implement" } if factory
    item["open_factory_ask"] = open_ask if open_ask
    @items << item
    @details[id] = item.except("current_stage", "waiting_on").merge(
      "stages" => stages || (factory ? [{ "id" => "st-#{id}", "stage_type" => "factory_job", "sequence" => 1, "status" => "completed",
                                          "started_at" => (created_at + 60).iso8601(3), "completed_at" => nil }] : []),
      "pull_requests" => [], "cost_summary" => { "total_cost_usd" => total_cost }
    )
    @node_runs_by_id[id] ||= []
    item
  end

  def add_node_run(work_item_id, id:, node_id:, started_at:, completed_at: nil, cost: nil, status: "completed")
    @node_runs_by_id[work_item_id] << {
      "id" => id, "stage_id" => "st-#{work_item_id}", "node_id" => node_id, "kind" => "droid", "status" => status,
      "cost_usd" => cost, "started_at" => started_at.iso8601(3), "completed_at" => completed_at&.iso8601(3),
      "duration_seconds" => completed_at && (completed_at - started_at).to_i, "iteration" => 0
    }
  end

  def add_ask(work_item_id, id:, jira_key:, kind:, opened_at:, answered_at: nil, resolution: nil, answered_by: nil)
    @asks << {
      "id" => id, "work_item_id" => work_item_id, "jira_key" => jira_key, "kind" => kind, "node_id" => "review",
      "state" => answered_at ? "answered" : "open", "opened_at" => opened_at.iso8601(3),
      "answered_at" => answered_at&.iso8601(3), "resolution" => resolution, "answered_by" => answered_by
    }
  end

  def touch(id, updated_at)
    item = @items.find { |i| i["id"] == id }
    item["updated_at"] = updated_at.iso8601(3)
    @details[id]["updated_at"] = item["updated_at"]
  end

  # --- Scarif::Client interface ---------------------------------------------------

  def me
    @calls << [:me]
    @me_body
  end

  def work_items(cursor: nil, limit: 100)
    @calls << [:work_items, cursor]
    sorted = @items.sort_by { |i| [i["updated_at"], i["id"]] }.reverse
    offset = cursor.to_i
    page = sorted[offset, page_size] || []
    more = offset + page_size < sorted.size
    Scarif::Client::Page.new(items: page, next_cursor: more ? (offset + page_size).to_s : nil, has_more: more)
  end

  def work_item(id)
    @calls << [:work_item, id]
    @details.fetch(id)
  end

  def node_runs(id)
    @calls << [:node_runs, id]
    @node_runs_by_id.fetch(id, [])
  end

  def factory_asks(jira_key:)
    @calls << [:factory_asks, jira_key]
    @asks.select { |a| a["jira_key"] == jira_key }
  end
end
