class WorkItemsController < ApplicationController
  def index
    @work_items = WorkItem.includes(:project, :batch, :agent_runs, :attention_spans, :time_drafts).order(updated_at: :desc)
    @work_items = @work_items.where(status: params[:status]) if params[:status].present?
  end

  def show
    @work_item = WorkItem.includes(:project, :batch, :agent_runs, pipeline_events: :person).find(params[:id])
  end
end
