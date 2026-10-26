# Stands in for Harvest::Client in tests. Keeps time entries in memory and
# answers like the real API: 404 for missing entries, and so on.
class FakeHarvestClient
  attr_reader :entries, :posted
  attr_accessor :timestamp_mode, :refuse_create, :refuse_delete, :refuse_read

  def initialize(live: true)
    @live = live
    @entries = {}
    @posted = []
    @next_id = 7000
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
    return Harvest::Client::Response.new(ok: true, dry_run: true, payload:) unless @live
    return Harvest::Client::Response.new(ok: false, dry_run: false, error: refuse_create, payload:) if refuse_create

    id = (@next_id += 1)
    @posted << payload
    @entries[id] = {
      "id" => id,
      "project" => { "id" => payload[:project_id] },
      "task" => { "id" => payload[:task_id] },
      "spent_date" => payload[:spent_date],
      "hours" => payload[:hours],
      "notes" => payload[:notes]
    }
    Harvest::Client::Response.new(ok: true, dry_run: false, entry_id: id, payload:)
  end

  def time_entry(id)
    raise Harvest::Client::Error.new("Harvest 500: boom", status: 500) if refuse_read
    @entries.fetch(id.to_i) { raise Harvest::Client::Error.new("Harvest 404: Not found", status: 404) }
  end

  def delete_time_entry(id)
    raise Harvest::Client::Error.new("Harvest 422: #{refuse_delete}", status: 422) if refuse_delete
    raise Harvest::Client::Error.new("Harvest 404: Not found", status: 404) unless @entries.key?(id.to_i)

    @entries.delete(id.to_i)
    true
  end
end
