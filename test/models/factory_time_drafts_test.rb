require "test_helper"

# The factory's working time on each ticket becomes time on the person's
# draft for that ticket, ready to approve and send to Harvest.
class FactoryTimeDraftsTest < ActiveSupport::TestCase
  D = Date.new(2026, 11, 10)

  setup do
    @person = Person.for_email!("kris@example.com")
    @t = Time.zone.parse("#{D} 09:00")
  end

  def factory_run(key, stage, from_min, to_min)
    common = { "jira_key" => key, "batch_id" => nil, "data" => { "stage_id" => "#{key}-#{stage}", "stage_type" => stage } }
    EventIngest.call(event_payload(common.merge("event_type" => "stage_claimed", "occurred_at" => (@t + from_min.minutes).iso8601)))
    return unless to_min

    EventIngest.call(event_payload(common.merge("event_type" => "stage_completed", "occurred_at" => (@t + to_min.minutes).iso8601)))
  end

  def drafts = DayAttribution.new(person: @person, date: D).write_drafts!.includes(:work_item).index_by { |d| d.work_item.jira_key }

  test "each ticket's factory time becomes a draft to approve" do
    factory_run("CRB-1", "plan", 0, 20)
    factory_run("CRB-1", "implement", 25, 85)
    by_key = drafts
    draft = by_key.fetch("CRB-1")
    assert_equal 80 * 60, draft.factory_seconds
    assert_equal "development", draft.activity
    assert_equal BigDecimal("1.33"), draft.hours
    assert_equal "draft", draft.status
    assert_match "includes 80m of factory time", draft.notes
  end

  test "tickets worked at the same time share it, so the day never exceeds real time" do
    factory_run("CRB-1", "implement", 0, 60)
    factory_run("CRB-2", "implement", 0, 60)
    by_key = drafts
    assert_equal 30 * 60, by_key["CRB-1"].factory_seconds
    assert_equal 30 * 60, by_key["CRB-2"].factory_seconds
  end

  test "full mode gives each ticket its whole time" do
    LedgerSetting.current.update!(factory_time_mode: "full")
    factory_run("CRB-1", "implement", 0, 60)
    factory_run("CRB-2", "implement", 0, 60)
    assert_equal [60 * 60, 60 * 60], drafts.values.map(&:factory_seconds)
  end

  test "time tracked by hand isn't counted twice" do
    factory_run("CRB-1", "implement", 0, 60)
    item = WorkItem.find_by!(jira_key: "CRB-1")
    AttentionSpan.create!(person: @person, work_item: item, activity: "review", started_at: @t + 10.minutes, last_seen_at: @t + 25.minutes)
    by_draft = DayAttribution.new(person: @person, date: D).write_drafts!.index_by(&:activity)
    assert_equal 15 * 60, by_draft["review"].direct_seconds
    assert_equal 45 * 60, by_draft["development"].factory_seconds
  end

  test "factory time can be turned off" do
    LedgerSetting.current.update!(factory_time_mode: "off")
    factory_run("CRB-1", "implement", 0, 60)
    assert_empty drafts
  end

  test "approved drafts don't change when more factory time arrives" do
    factory_run("CRB-1", "implement", 0, 30)
    drafts["CRB-1"].update!(status: "approved")
    factory_run("CRB-1", "verify", 40, 70)
    assert_equal 30 * 60, drafts["CRB-1"].factory_seconds
  end

  test "factory time can be logged as another activity" do
    LedgerSetting.current.update!(factory_time_activity: "supervision")
    factory_run("CRB-1", "implement", 0, 30)
    assert_equal "supervision", drafts["CRB-1"].activity
  end
end
