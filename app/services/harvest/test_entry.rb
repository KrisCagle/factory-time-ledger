module Harvest
  # End-to-end check against the live account: creates a tiny entry on a
  # mapped project, reads it back, deletes it, and confirms it's gone. Proves
  # the token can write to that project without leaving anything behind.
  class TestEntry
    HOURS = 0.01
    NOTE = "factory-time-ledger connection test (deleted automatically)".freeze

    Step = Struct.new(:name, :ok, :detail, keyword_init: true)
    Outcome = Struct.new(:ok, :message, :steps, keyword_init: true)

    def self.call(project:, client: Client.new, setting: LedgerSetting.current) = new(project, client, setting).call

    def initialize(project, client, setting)
      @project = project
      @client = client
      @setting = setting
      @steps = []
    end

    def call
      return finish(false, "Harvest isn't connected, so there's nothing to test.") if @client.dry_run?

      task_id = @project.harvest_dev_task_id
      return finish(false, "#{@project.name} needs a Harvest project and Development task first.") if @project.harvest_project_id.blank? || task_id.blank?

      if (problem = Guard.problem(project: @project, task_id:, setting: @setting))
        return finish(false, "Can't test #{@project.name}: #{problem}")
      end

      payload = { project_id: @project.harvest_project_id, task_id:, spent_date: Date.current.iso8601, hours: HOURS, notes: NOTE }

      created = @client.create_time_entry(payload)
      unless created.ok
        step("Create a test entry", false, created.error)
        return finish(false, "Harvest refused the test entry: #{created.error}")
      end
      entry_id = created.entry_id
      step("Create a test entry", true, "entry ##{entry_id} on #{harvest_label(task_id)}")

      begin
        diffs = VerifyEntry.differences(@client.time_entry(entry_id), payload)
        step("Read it back", diffs.empty?, diffs.empty? ? "matches what was sent" : "differs: #{diffs.join(', ')}")
      rescue Client::Error => e
        step("Read it back", false, e.message)
      end

      begin
        @client.delete_time_entry(entry_id)
        step("Delete it", true, "removed from Harvest")
      rescue Client::Error => e
        step("Delete it", false, e.message)
        return finish(false, "The test entry ##{entry_id} was created but couldn't be deleted (#{e.message}). Delete it in Harvest by hand.")
      end

      begin
        @client.time_entry(entry_id)
        step("Confirm it's gone", false, "entry ##{entry_id} still exists")
      rescue Client::Error => e
        step("Confirm it's gone", e.not_found?, e.not_found? ? "not found, as expected" : e.message)
      end

      ok = @steps.all?(&:ok)
      finish(ok, ok ? "Test entry passed on #{@project.name}: created, verified, and deleted in Harvest." : "Test entry had problems. See the steps below.")
    end

    private

      def harvest_label(task_id)
        hp = HarvestProject.find_by(harvest_id: @project.harvest_project_id)
        hp ? "#{hp.name} / #{hp.task_name(task_id)}" : "project ##{@project.harvest_project_id}"
      end

      def step(name, ok, detail) = @steps << Step.new(name:, ok:, detail:)

      def finish(ok, message)
        @setting.update!(
          harvest_test_log: @steps.map(&:to_h).map(&:stringify_keys),
          harvest_test_passed_at: ok ? Time.current : @setting.harvest_test_passed_at
        )
        Outcome.new(ok:, message:, steps: @steps)
      end
  end
end
