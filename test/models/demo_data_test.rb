require "test_helper"

class DemoDataTest < ActiveSupport::TestCase
  test "loads a full demo day" do
    result = DemoData.load!
    assert_equal 8, result[:tickets]
    assert_equal 2, result[:batches]
    assert DemoData.present?
    assert TimeDraft.where(status: "approved").exists?
  end

  test "removing demo data keeps real tickets, projects, and people" do
    DemoData.load!
    EventIngest.call(event_payload("jira_key" => "REAL-1", "repo" => "twinsunllc/real-app", "batch_id" => nil, "person_email" => "kris@example.com"))
    real_person = Person.find_by!(email: "kris@example.com")
    AttentionSpan.create!(person: real_person, work_item: WorkItem.find_by!(jira_key: "REAL-1"), activity: "review",
                          started_at: 1.hour.ago, last_seen_at: 30.minutes.ago)

    counts = DemoData.remove!

    assert_equal 8, counts[:tickets]
    refute DemoData.present?
    assert_equal ["REAL-1"], WorkItem.pluck(:jira_key)
    assert_equal ["twinsunllc/real-app"], Project.pluck(:repo)
    assert_equal ["kris@example.com"], Person.pluck(:email)
    assert_equal 1, AttentionSpan.count
    assert_equal 0, Batch.count
    assert_equal 0, TimeDraft.count
  end

  test "seeds skip demo data when tickets already exist" do
    EventIngest.call(event_payload("jira_key" => "REAL-1"))
    assert_output(/skipping demo data/) { Rails.application.load_seed }
    refute DemoData.present?
  end
end
