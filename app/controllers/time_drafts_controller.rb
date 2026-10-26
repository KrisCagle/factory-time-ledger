class TimeDraftsController < ApplicationController
  before_action :require_person!

  def index
    @drafts = drafts_for_day.includes(:person, work_item: :project)
    @harvest_live = Harvest::Client.configured?
  end

  # Re-runs attribution for the day and refreshes unapproved drafts.
  def generate
    DayAttribution.new(person: current_person, date: selected_date).write_drafts!
    redirect_to time_drafts_path(date: selected_date), notice: "Drafts refreshed from today's attention data."
  end

  def update
    draft = current_person.time_drafts.find(params[:id])
    if draft.update(draft_params)
      redirect_to time_drafts_path(date: draft.spent_on), notice: "#{draft.work_item.jira_key} updated."
    else
      redirect_to time_drafts_path(date: draft.spent_on), alert: draft.errors.full_messages.to_sentence
    end
  end

  def approve_all
    drafts_for_day.where(status: "draft").update_all(status: "approved", updated_at: Time.current)
    redirect_to time_drafts_path(date: selected_date), notice: "All drafts approved."
  end

  def send_approved
    outcomes = drafts_for_day.where(status: "approved").map { |draft| Harvest::SendDraft.call(draft) }
    if outcomes.empty?
      redirect_to time_drafts_path(date: selected_date), alert: "Nothing approved to send."
    else
      flash[:notice] = outcomes.select(&:ok).map(&:message).join(" · ").presence
      flash[:alert] = outcomes.reject(&:ok).map(&:message).join(" · ").presence
      redirect_to time_drafts_path(date: selected_date)
    end
  end

  def verify
    draft = current_person.time_drafts.find(params[:id])
    outcome = Harvest::VerifyEntry.call(draft)
    redirect_to time_drafts_path(date: draft.spent_on), (outcome.ok ? :notice : :alert) => outcome.message
  end

  def undo
    draft = current_person.time_drafts.find(params[:id])
    outcome = Harvest::UndoDraft.call(draft)
    redirect_to time_drafts_path(date: draft.spent_on), (outcome.ok ? :notice : :alert) => outcome.message
  end

  private

    def drafts_for_day
      TimeDraft.for_day(current_person, selected_date).order(:created_at)
    end

    def draft_params
      params.require(:time_draft).permit(:hours, :notes, :status).tap do |p|
        p.delete(:status) unless %w[draft approved].include?(p[:status])
      end
    end
end
