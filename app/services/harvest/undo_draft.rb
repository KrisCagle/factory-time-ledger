module Harvest
  # Deletes a sent draft's entry from Harvest and puts the draft back to
  # approved, so it can be corrected and sent again.
  class UndoDraft
    Outcome = Struct.new(:ok, :message, keyword_init: true)

    def self.call(draft, client: Client.new) = new(draft, client).call

    def initialize(draft, client)
      @draft = draft
      @client = client
    end

    def call
      return Outcome.new(ok: false, message: "Only sent drafts can be undone") unless @draft.status == "sent" && @draft.harvest_time_entry_id

      entry_id = @draft.harvest_time_entry_id
      begin
        @client.delete_time_entry(entry_id)
      rescue Client::Error => e
        raise unless e.not_found? # already gone in Harvest is fine
      end

      @draft.update!(status: "approved", harvest_time_entry_id: nil, sent_at: nil,
                     harvest_verified_at: nil, harvest_verify_note: nil, last_error: nil)
      Outcome.new(ok: true, message: "Removed #{@draft.work_item.jira_key} from Harvest (entry ##{entry_id}). The draft is back to approved.")
    rescue Client::Error => e
      @draft.update!(last_error: "Couldn't undo: #{e.message}")
      Outcome.new(ok: false, message: "Couldn't remove #{@draft.work_item.jira_key} from Harvest: #{e.message}")
    end
  end
end
