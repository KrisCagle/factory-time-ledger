class PeopleController < ApplicationController
  def create
    person = Person.new(params.require(:person).permit(:name, :email, :harvest_user_id))
    if person.save
      session[:person_id] = person.id
      redirect_to settings_path, notice: "#{person.name} added."
    else
      redirect_to settings_path, alert: person.errors.full_messages.to_sentence
    end
  end
end
