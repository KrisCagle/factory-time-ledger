class HarvestConnectionsController < ApplicationController
  def check
    outcome = Harvest::CheckConnection.call
    redirect_to settings_path(anchor: "harvest"), (outcome.ok ? :notice : :alert) => outcome.message
  end

  def load_projects
    outcome = Harvest::SyncProjects.call
    redirect_to settings_path(anchor: "harvest"), (outcome.ok ? :notice : :alert) => outcome.message
  end
end
