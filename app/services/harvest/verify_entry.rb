module Harvest
  # Reads a sent entry back from Harvest and checks it matches what was sent.
  class VerifyEntry
    Outcome = Struct.new(:ok, :message, keyword_init: true)

    # Compares a Harvest time entry to the payload that created it. Returns a
    # list of differences (empty when it matches).
    def self.differences(entry, payload)
      payload = payload.to_h.stringify_keys
      diffs = []
      diffs << "project" if entry.dig("project", "id").to_i != payload["project_id"].to_i
      diffs << "task" if entry.dig("task", "id").to_i != payload["task_id"].to_i
      diffs << "date" if entry["spent_date"].to_s != payload["spent_date"].to_s
      diffs << "hours" if (entry["hours"].to_f - payload["hours"].to_f).abs > 0.01
      diffs
    end

    def self.call(draft, client: Client.new) = new(draft, client).call

    def initialize(draft, client)
      @draft = draft
      @client = client
    end

    def call
      return Outcome.new(ok: false, message: "Only sent drafts can be verified") unless @draft.status == "sent" && @draft.harvest_time_entry_id

      entry = @client.time_entry(@draft.harvest_time_entry_id)
      diffs = self.class.differences(entry, @draft.last_payload)
      if diffs.empty?
        @draft.update!(harvest_verified_at: Time.current, harvest_verify_note: nil)
        Outcome.new(ok: true, message: "#{@draft.work_item.jira_key} verified in Harvest")
      else
        note = "Harvest entry ##{@draft.harvest_time_entry_id} differs from what was sent (#{diffs.join(', ')}). It may have been edited in Harvest."
        @draft.update!(harvest_verified_at: nil, harvest_verify_note: note)
        Outcome.new(ok: false, message: note)
      end
    rescue Client::Error => e
      note = e.not_found? ? "Harvest entry ##{@draft.harvest_time_entry_id} no longer exists in Harvest." : "Couldn't verify: #{e.message}"
      @draft.update!(harvest_verified_at: nil, harvest_verify_note: note)
      Outcome.new(ok: false, message: note)
    end
  end
end
