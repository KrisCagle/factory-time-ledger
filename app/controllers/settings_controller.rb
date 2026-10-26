class SettingsController < ApplicationController
  def show
    @setting = LedgerSetting.current
    @projects = Project.order(:name)
    @new_project = Project.new
    @new_person = Person.new
    @harvest_configured = Harvest::Client.configured?
    @harvest_projects = HarvestProject.active.ordered.to_a
    @checklist = GoLiveChecklist.new(setting: @setting)
    @testable_projects = @checklist.real_mapped_projects
    @demo_present = DemoData.present?
  end

  def update
    setting = LedgerSetting.current
    if setting.update(params.require(:ledger_setting).permit(:split_rule, :idle_gap_minutes, :rounding_minutes))
      redirect_to settings_path, notice: "Settings saved."
    else
      redirect_to settings_path, alert: setting.errors.full_messages.to_sentence
    end
  end
end
