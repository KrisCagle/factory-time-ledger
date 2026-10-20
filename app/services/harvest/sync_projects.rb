module Harvest
  # Pulls the token owner's Harvest project assignments (with their tasks)
  # into harvest_projects. Projects no longer assigned are removed.
  class SyncProjects
    Outcome = Struct.new(:ok, :message, :count, keyword_init: true)

    def self.call(client: Client.new, setting: LedgerSetting.current) = new(client, setting).call

    def initialize(client, setting)
      @client = client
      @setting = setting
    end

    def call
      assignments = @client.project_assignments
      seen = []

      HarvestProject.transaction do
        assignments.each do |assignment|
          project = assignment["project"] || {}
          next if project["id"].blank?

          tasks = Array(assignment["task_assignments"])
                  .select { |ta| ta["is_active"] != false && ta.dig("task", "id").present? }
                  .map { |ta| { "id" => ta.dig("task", "id"), "name" => ta.dig("task", "name"), "billable" => ta["billable"] } }
                  .sort_by { |task| task["name"].to_s }

          record = HarvestProject.find_or_initialize_by(harvest_id: project["id"])
          record.update!(
            name: project["name"],
            code: project["code"],
            client_name: assignment.dig("client", "name"),
            is_active: assignment["is_active"] != false,
            tasks:
          )
          seen << record.id
        end
        HarvestProject.where.not(id: seen).delete_all
        @setting.update!(harvest_projects_synced_at: Time.current)
      end

      Outcome.new(ok: true, count: seen.size, message: "Loaded #{seen.size} Harvest #{'project'.pluralize(seen.size)} you're assigned to.")
    rescue Client::Error => e
      Outcome.new(ok: false, count: 0, message: e.message)
    end
  end
end
