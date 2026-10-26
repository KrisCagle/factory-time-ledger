# The steps to go live with Harvest, each with whether it's done. Mirrors the
# "Harvest live" milestone: token connected, projects mapped, one real entry
# sent and verified.
class GoLiveChecklist
  Step = Struct.new(:title, :done, :detail, keyword_init: true)

  def initialize(setting: LedgerSetting.current)
    @setting = setting
  end

  def steps
    @steps ||= [
      Step.new(title: "Add your Harvest token to .env",
               done: Harvest::Client.configured?,
               detail: "HARVEST_ACCESS_TOKEN and HARVEST_ACCOUNT_ID, then restart bin/dev"),
      Step.new(title: "Test the connection",
               done: @setting.harvest_checked? && @setting.harvest_timestamp_mode == false,
               detail: "Confirms the token works and the account tracks durations"),
      Step.new(title: "Load your projects from Harvest",
               done: @setting.harvest_projects_loaded? && HarvestProject.exists?,
               detail: "Pulls in the projects and tasks you're assigned to"),
      Step.new(title: "Map a repo to a Harvest project and tasks",
               done: real_mapped_projects.any?,
               detail: "In Projects → Harvest below"),
      Step.new(title: "Run a test entry",
               done: @setting.harvest_test_passed_at.present?,
               detail: "Creates, verifies, and deletes a 0.01h entry"),
      Step.new(title: "Send and verify a real entry",
               done: TimeDraft.where.not(harvest_verified_at: nil).exists?,
               detail: "Track time on a real ticket, approve the draft, and send it")
    ]
  end

  def complete? = steps.all?(&:done)
  def done_count = steps.count(&:done)

  # Mapped projects whose Harvest project and tasks are all in the loaded list.
  def real_mapped_projects
    loaded = HarvestProject.all.index_by(&:harvest_id)
    Project.all.select do |project|
      hp = loaded[project.harvest_project_id]
      hp && project.harvest_mapped? &&
        [project.harvest_dev_task_id, project.harvest_qa_task_id, project.harvest_supervision_task_id].all? { |id| hp.has_task?(id) }
    end
  end
end
