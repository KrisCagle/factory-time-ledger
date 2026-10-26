class HarvestConnectionsController < ApplicationController
  def check
    outcome = Harvest::CheckConnection.call
    session[:person_id] ||= outcome.person&.id
    redirect_to settings_path(anchor: "harvest"), (outcome.ok ? :notice : :alert) => outcome.message
  end

  def load_projects
    outcome = Harvest::SyncProjects.call
    redirect_to settings_path(anchor: "harvest"), (outcome.ok ? :notice : :alert) => outcome.message
  end

  def test_entry
    project = Project.find(params.require(:project_id))
    outcome = Harvest::TestEntry.call(project:)
    redirect_to settings_path(anchor: "harvest"), (outcome.ok ? :notice : :alert) => outcome.message
  end
end
