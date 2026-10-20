class TodayController < ApplicationController
  before_action :require_person!

  def show
    @attribution = DayAttribution.new(person: current_person, date: selected_date)
    @result = @attribution.result
    @lines = @result.lines.sort_by { |l| -l.total_seconds }
    @recent_items = WorkItem.where.not(status: %w[done cancelled]).order(updated_at: :desc).limit(12)
  end
end
