# Finds and removes the demo data loaded by db/seeds.rb, leaving real data
# alone. Demo records are recognisable by their repo prefix, people's email
# addresses, and attention-span source.
class DemoData
  REPO_PREFIX = "twinsun-demo/".freeze
  EMAIL_PATTERN = "demo.%@example.com".freeze

  def self.present? = demo_projects.exists? || demo_people.exists?
  def self.load! = Loader.call

  def self.demo_projects = Project.where("repo LIKE ?", "#{REPO_PREFIX}%")
  def self.demo_people = Person.where("email LIKE ?", EMAIL_PATTERN)

  # Returns counts of what was removed.
  def self.remove!
    counts = Hash.new(0)
    ActiveRecord::Base.transaction do
      items = WorkItem.where(project_id: demo_projects.select(:id))
      batch_ids = items.where.not(batch_id: nil).distinct.pluck(:batch_id)

      counts[:attention_spans] += AttentionSpan.where(source: "demo").delete_all
      counts[:attention_spans] += AttentionSpan.where(work_item_id: items.select(:id)).delete_all
      # Demo drafts can never be sent: their made-up Harvest IDs fail the live guards.
      counts[:time_drafts] += TimeDraft.where(work_item_id: items.select(:id)).delete_all

      counts[:tickets] = items.count
      PipelineEvent.where(work_item_id: items.select(:id)).delete_all
      AgentRun.where(work_item_id: items.select(:id)).delete_all
      items.delete_all

      # A batch goes only if nothing real is left in it.
      empty_batches = Batch.where(id: batch_ids).where.not(id: WorkItem.where.not(batch_id: nil).select(:batch_id))
      AttentionSpan.where(batch_id: empty_batches.select(:id)).where(source: "demo").delete_all
      AttentionSpan.where(batch_id: empty_batches.select(:id)).update_all(batch_id: nil)
      counts[:batches] = empty_batches.delete_all

      counts[:projects] = demo_projects.delete_all
      people = demo_people
      TimeDraft.where(person_id: people.select(:id)).delete_all
      AttentionSpan.where(person_id: people.select(:id)).delete_all
      Batch.where(started_by_id: people.select(:id)).update_all(started_by_id: nil)
      PipelineEvent.where(person_id: people.select(:id)).update_all(person_id: nil)
      counts[:people] = people.delete_all
    end
    counts
  end
end
