# Stands in for ForemanApi::Client in tests. Answers follow twinsunllc/foreman:
# GET /inferred-runs/{id} is { "build", "run" } with the run's `tasks`
# (lib/foreman/inferred_runs.rb), and GET /stories/{key}/timeline is
# { "story", "runs", "entries" }.
class FakeForemanClient
  attr_accessor :runs, :timelines, :timeline_status, :run_status
  attr_reader :calls

  def initialize
    @runs = {}
    @timelines = {}
    @timeline_status = nil
    @run_status = nil
    @calls = []
  end

  def add_run(key, tasks:, position: "implement", state: "working", status: "running", client: "acme")
    @runs[key] = {
      "build" => "2026-11-10T15:00:00Z",
      "run" => {
        "id" => "jira:#{key}", "source" => "jira", "subject" => key, "title" => "Story #{key}",
        "workflow" => "deliver-story", "workflow_version" => "1.2.0", "client" => client, "scope" => "client:#{client}",
        "position" => position, "status" => status, "state" => state, "dormant" => false,
        "started_at" => tasks.first&.dig("enqueued_at"), "ended_at" => nil, "tasks" => tasks
      }
    }
  end

  def self.task(node, entered, claimed: nil, left: nil, implementor: nil, type: "person", source: "status", outcome: nil)
    { "id" => "t-#{node}", "node" => node, "contract" => node, "enqueued_at" => entered&.iso8601,
      "claimed_at" => claimed&.iso8601, "ended_at" => left&.iso8601, "implementor" => implementor,
      "implementor_type" => type, "claim_source" => source, "outcome" => outcome }.compact
  end

  def inferred_run(key)
    @calls << [:inferred_run, key]
    raise ForemanApi::Client::Error.new("Foreman #{run_status}", status: run_status) if run_status
    @runs.fetch(key) { raise ForemanApi::Client::Error.new("Foreman 404: no such run", status: 404) }
  end

  def story_timeline(key)
    @calls << [:story_timeline, key]
    raise ForemanApi::Client::Error.new("Foreman #{timeline_status}", status: timeline_status) if timeline_status
    @timelines.fetch(key) { raise ForemanApi::Client::Error.new("Foreman 404: no runs", status: 404) }
  end
end
