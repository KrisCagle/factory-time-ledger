module Harvest
  # Checks that must pass before anything is written to a live Harvest
  # account, so demo data or a mistyped ID can't land on the wrong project.
  # Returns a message describing the first problem, or nil when it's safe.
  module Guard
    def self.problem(project:, task_id:, setting: LedgerSetting.current)
      return "run Test connection in Settings first." unless setting.harvest_checked?
      return "this Harvest account tracks start and end times, which this app can't send yet." if setting.harvest_timestamp_mode
      return "load your projects from Harvest in Settings first." unless setting.harvest_projects_loaded?

      harvest_project = HarvestProject.find_by(harvest_id: project.harvest_project_id)
      return "Harvest project ##{project.harvest_project_id} isn't one of your Harvest projects. Re-pick it in Settings." unless harvest_project
      return "task ##{task_id} isn't assigned to #{harvest_project.name} in Harvest. Re-pick it in Settings." unless harvest_project.has_task?(task_id)

      nil
    end
  end
end
