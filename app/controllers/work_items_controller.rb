class WorkItemsController < ApplicationController
  def index
    @work_items = WorkItem.includes(:project, :batch, :agent_runs, :attention_spans, :time_drafts).order(updated_at: :desc)
    @work_items = @work_items.where(status: params[:status]) if params[:status].present?
    @projects = Project.order(:name)
  end

  # Adds a ticket by hand, for work that isn't coming from a factory yet.
  def create
    attrs = params.require(:work_item).permit(:jira_key, :summary, :repo)
    if attrs[:jira_key].blank? || attrs[:repo].blank?
      return redirect_to(work_items_path, alert: "A Jira key and project are required.")
    end

    EventIngest.call(
      "source" => "manual", "event_id" => SecureRandom.uuid, "event_type" => "ticket_added",
      "occurred_at" => Time.current.iso8601, "jira_key" => attrs[:jira_key].strip, "summary" => attrs[:summary],
      "repo" => attrs[:repo].strip, "person_email" => current_person&.email
    )
    item = WorkItem.find_by!(jira_key: attrs[:jira_key].strip.upcase)
    redirect_to work_item_path(item), notice: "#{item.jira_key} added. Use Track active time to log work on it."
  end

  def show
    @work_item = WorkItem.includes(:project, :batch, :agent_runs, pipeline_events: :person).find(params[:id])
  end
end
