module Harvest
  # Sends one approved draft to Harvest. In dry-run mode the draft stays
  # approved and keeps the payload it would have sent, so you can inspect it.
  #
  # When live, it refuses to send unless:
  #   - Test connection has passed and the account tracks durations
  #   - projects have been loaded from Harvest, the mapped project is one of
  #     them, and the mapped task is assigned to that project
  # so demo data or a mistyped ID can never land on the wrong Harvest project.
  class SendDraft
    Outcome = Struct.new(:ok, :dry_run, :message, keyword_init: true)

    def self.call(draft, client: Client.new, setting: LedgerSetting.current) = new(draft, client, setting).call

    def initialize(draft, client, setting)
      @draft = draft
      @client = client
      @setting = setting
    end

    def call
      return refuse("Only approved drafts can be sent") unless @draft.status == "approved"

      key = @draft.work_item.jira_key
      project = @draft.work_item.project
      return refuse("#{key} has no project. Map its repo in Settings.") unless project
      return refuse("#{project.name} has no Harvest project. Pick one in Settings.") if project.harvest_project_id.blank?

      task_id = project.harvest_task_id_for(@draft.activity)
      return refuse("#{project.name} has no Harvest task for #{Activity.label(@draft.activity)}. Pick one in Settings.") if task_id.blank?

      unless @client.dry_run?
        problem = live_guard(project, task_id)
        return refuse("#{key}: #{problem}") if problem
      end

      payload = {
        project_id: project.harvest_project_id,
        task_id:,
        spent_date: @draft.spent_on.iso8601,
        hours: @draft.hours.to_f,
        notes: @draft.notes
      }
      user_id = @draft.person.harvest_user_id
      payload[:user_id] = user_id if user_id.present? && user_id != @setting.harvest_user_id

      response = @client.create_time_entry(payload)
      if response.dry_run
        @draft.update!(last_payload: payload, last_error: nil)
        Outcome.new(ok: true, dry_run: true, message: "Dry run: #{key} would log #{@draft.hours}h")
      elsif response.ok
        @draft.update!(status: "sent", harvest_time_entry_id: response.entry_id, sent_at: Time.current, last_payload: payload, last_error: nil)
        Outcome.new(ok: true, dry_run: false, message: "Sent #{key} (#{@draft.hours}h)")
      else
        @draft.update!(status: "failed", last_payload: payload, last_error: response.error)
        Outcome.new(ok: false, dry_run: false, message: "#{key}: #{response.error}")
      end
    end

    private

      def live_guard(project, task_id)
        return "run Test connection in Settings first." unless @setting.harvest_checked?
        return "this Harvest account tracks start and end times, which this app can't send yet." if @setting.harvest_timestamp_mode
        return "load your projects from Harvest in Settings first." unless @setting.harvest_projects_loaded?

        harvest_project = HarvestProject.find_by(harvest_id: project.harvest_project_id)
        return "Harvest project ##{project.harvest_project_id} isn't one of your Harvest projects. Re-pick it in Settings." unless harvest_project
        return "task ##{task_id} isn't assigned to #{harvest_project.name} in Harvest. Re-pick it in Settings." unless harvest_project.has_task?(task_id)

        nil
      end

      def refuse(message)
        @draft.update!(last_error: message)
        Outcome.new(ok: false, dry_run: false, message:)
      end
  end
end
