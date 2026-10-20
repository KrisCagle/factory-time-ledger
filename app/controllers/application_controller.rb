# No login in v1: it runs on your machine. The header's person picker sets
# whose time you're looking at.
class ApplicationController < ActionController::Base
  helper_method :current_person, :people, :selected_date

  private

    def people = @people ||= Person.order(:name).to_a

    def current_person
      @current_person ||= begin
        session[:person_id] = params[:person_id] if params[:person_id].present?
        Person.find_by(id: session[:person_id]) || people.first
      end
    end

    def selected_date
      @selected_date ||= begin
        Date.iso8601(params[:date].to_s)
      rescue Date::Error
        Date.current
      end
    end

    def require_person!
      redirect_to settings_path, alert: "Add a person first (or run bin/setup to load demo data)." unless current_person
    end
end
