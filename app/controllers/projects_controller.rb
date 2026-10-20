class ProjectsController < ApplicationController
  def create
    project = Project.new(project_params)
    if project.save
      redirect_to settings_path, notice: "#{project.name} added."
    else
      redirect_to settings_path, alert: project.errors.full_messages.to_sentence
    end
  end

  def update
    project = Project.find(params[:id])
    if project.update(project_params)
      redirect_to settings_path, notice: "#{project.name} saved."
    else
      redirect_to settings_path, alert: project.errors.full_messages.to_sentence
    end
  end

  private

    def project_params
      params.require(:project).permit(:repo, :name, :harvest_project_id, :harvest_dev_task_id, :harvest_qa_task_id, :harvest_supervision_task_id)
    end
end
