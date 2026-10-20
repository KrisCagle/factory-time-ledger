module Harvest
  # Sends one approved draft to Harvest. In dry-run mode the draft stays
  # approved and keeps the payload it would have sent, so you can inspect it.
  class SendDraft
    Outcome = Struct.new(:ok, :dry_run, :message, keyword_init: true)

    def self.call(draft, client: Client.new) = new(draft, client).call

    def initialize(draft, client)
      @draft = draft
      @client = client
    end

    def call
      return fail!("Only approved drafts can be sent") unless @draft.status == "approved"

      project = @draft.work_item.project
      return fail!("#{@draft.work_item.jira_key} has no project. Map its repo in Settings.") unless project
      return fail!("#{project.name} has no Harvest project ID. Add it in Settings.") if project.harvest_project_id.blank?

      task_id = project.harvest_task_id_for(@draft.activity)
      return fail!("#{project.name} has no Harvest task for #{Activity.label(@draft.activity)}. Add it in Settings.") if task_id.blank?

      payload = {
        project_id: project.harvest_project_id,
        task_id:,
        spent_date: @draft.spent_on.iso8601,
        hours: @draft.hours.to_f,
        notes: @draft.notes
      }
      payload[:user_id] = @draft.person.harvest_user_id if @draft.person.harvest_user_id.present?

      response = @client.create_time_entry(payload)
      if response.dry_run
        @draft.update!(last_payload: payload, last_error: nil)
        Outcome.new(ok: true, dry_run: true, message: "Dry run: #{@draft.work_item.jira_key} would log #{@draft.hours}h")
      elsif response.ok
        @draft.update!(status: "sent", harvest_time_entry_id: response.entry_id, sent_at: Time.current, last_payload: payload, last_error: nil)
        Outcome.new(ok: true, dry_run: false, message: "Sent #{@draft.work_item.jira_key} (#{@draft.hours}h)")
      else
        @draft.update!(status: "failed", last_payload: payload, last_error: response.error)
        Outcome.new(ok: false, dry_run: false, message: "#{@draft.work_item.jira_key}: #{response.error}")
      end
    end

    private

      def fail!(message)
        @draft.update!(last_error: message)
        Outcome.new(ok: false, dry_run: false, message:)
      end
  end
end
