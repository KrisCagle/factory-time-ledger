class DemoDataController < ApplicationController
  def destroy
    counts = DemoData.remove!
    session.delete(:person_id)
    redirect_to settings_path, notice: "Demo data removed (#{counts[:tickets]} tickets, #{counts[:batches]} batches, #{counts[:people]} people)."
  end
end
