# Demo data so you can click through without connecting anything.
# Dates are relative to today, so the demo always looks current:
#   - the previous weekday has a full day across a 5-ticket batch
#   - today has a morning on a second, smaller batch
#
# Events go through EventIngest, the same path real factories use.
# Re-running replaces the demo data (bin/setup drops the database first).

puts "Loading demo data..."

Time.zone = Rails.application.config.time_zone
today = Date.current
yesterday = today.prev_weekday

def at(date, hhmm) = Time.zone.parse("#{date} #{hhmm}")

LedgerSetting.current.update!(split_rule: "agent_points", idle_gap_minutes: 3, rounding_minutes: 1)

dev = Person.for_email!("demo.developer@example.com", name: "Demo Developer")
Person.for_email!("demo.reviewer@example.com", name: "Demo Reviewer")

Project.for_repo!("twinsun-demo/acme-portal").update!(
  name: "Acme Portal", harvest_project_id: 11_111_111,
  harvest_dev_task_id: 2_000_001, harvest_qa_task_id: 2_000_002, harvest_supervision_task_id: 2_000_003
)
# Left unmapped on purpose, to show how missing Harvest IDs are flagged.
Project.for_repo!("twinsun-demo/beacon-api").update!(name: "Beacon API")

@seq = 0
def event!(source:, type:, at:, key:, batch:, repo:, summary: nil, points: nil, person: nil, batch_label: nil, data: {})
  @seq += 1
  EventIngest.call(
    "source" => source, "event_id" => "demo-#{@seq}", "event_type" => type,
    "occurred_at" => at.iso8601, "jira_key" => key, "summary" => summary,
    "repo" => repo, "batch_id" => batch, "batch_label" => batch_label,
    "agent_points" => points, "person_email" => person, "data" => data
  )
end

# A typical factory run: plan, implement, PR, CI, wait for a human, review.
def run_ticket!(source:, key:, summary:, points:, repo:, batch:, batch_label:, date:, start:, plan_cost:, impl_cost:, impl_minutes:, review_at:, outcome:, reviewer:)
  t = at(date, start)
  common = { source:, key:, batch:, repo:, batch_label: }
  event!(**common, type: "pipeline_started", at: t, summary:, points:, person: "demo.developer@example.com")
  event!(**common, type: "stage_claimed", at: t + 2.minutes, data: { "stage_id" => "#{key}-plan", "stage_type" => "plan" })
  event!(**common, type: "stage_completed", at: t + 11.minutes, data: { "stage_id" => "#{key}-plan", "stage_type" => "plan", "cost_usd" => plan_cost, "tokens" => 48_000 })
  event!(**common, type: "stage_claimed", at: t + 12.minutes, data: { "stage_id" => "#{key}-impl", "stage_type" => "implement" })
  done = t + 12.minutes + impl_minutes.minutes
  event!(**common, type: "stage_completed", at: done, data: { "stage_id" => "#{key}-impl", "stage_type" => "implement", "cost_usd" => impl_cost, "tokens" => 310_000 })
  event!(**common, type: "pr_created", at: done + 1.minute, data: { "pr_number" => 400 + @seq })
  event!(**common, type: "ci_check", at: done + 9.minutes, data: { "conclusion" => "success" })
  event!(**common, type: "wait_human_entered", at: done + 10.minutes, data: { "reason" => "human_review" })

  review = at(date, review_at)
  if outcome == :changes
    event!(**common, type: "human_review_changes_requested", at: review, person: reviewer)
    event!(**common, type: "stage_claimed", at: review + 2.minutes, data: { "stage_id" => "#{key}-rework", "stage_type" => "rework" })
    event!(**common, type: "stage_completed", at: review + 40.minutes, data: { "stage_id" => "#{key}-rework", "stage_type" => "rework", "cost_usd" => 1.42, "tokens" => 120_000 })
    event!(**common, type: "wait_human_entered", at: review + 45.minutes, data: { "reason" => "human_review" })
  else
    event!(**common, type: "wait_human_resolved", at: review, person: reviewer)
    event!(**common, type: "human_review_approved", at: review + 1.minute, person: reviewer)
    event!(**common, type: "pr_merged", at: review + 3.minutes)
    event!(**common, type: "pipeline_completed", at: review + 4.minutes)
  end
end

me = "demo.developer@example.com"

# --- Previous weekday: 5-ticket batch through ai-dev-factory ---------------
acme = { source: "ai-dev-factory", repo: "twinsun-demo/acme-portal", batch: "acme-morning", batch_label: "Acme morning batch", date: yesterday, reviewer: me }
run_ticket!(**acme, key: "ACME-101", summary: "Add CSV export to invoices list", points: 1, start: "09:05", plan_cost: 0.38, impl_cost: 2.10, impl_minutes: 45, review_at: "10:50", outcome: :approved)
run_ticket!(**acme, key: "ACME-102", summary: "Fix timezone bug in appointment reminders", points: 2, start: "09:05", plan_cost: 0.41, impl_cost: 3.35, impl_minutes: 70, review_at: "11:05", outcome: :approved)
run_ticket!(**acme, key: "ACME-103", summary: "Patient search with fuzzy matching", points: 5, start: "09:06", plan_cost: 0.77, impl_cost: 8.90, impl_minutes: 130, review_at: "11:55", outcome: :changes)
run_ticket!(**acme, key: "ACME-104", summary: "Paginate the audit log API", points: 3, start: "09:06", plan_cost: 0.52, impl_cost: 4.60, impl_minutes: 95, review_at: "14:10", outcome: :approved)
run_ticket!(**acme, key: "ACME-105", summary: "Copy updates on onboarding screens", points: 1, start: "09:07", plan_cost: 0.22, impl_cost: 1.05, impl_minutes: 25, review_at: "15:20", outcome: :approved)

acme_batch = Batch.find_by!(source: "ai-dev-factory", external_id: "acme-morning")
item = ->(key) { WorkItem.find_by!(jira_key: key) }

span = ->(date, from, to, activity, work_item: nil, batch: nil) do
  AttentionSpan.create!(person: dev, work_item:, batch:, activity:, source: "demo", started_at: at(date, from), last_seen_at: at(date, to))
end

span.(yesterday, "09:00", "09:20", "supervision", batch: acme_batch)        # writing the batch kickoff
span.(yesterday, "09:20", "09:35", "development")                          # email, nothing ticket-related
span.(yesterday, "10:30", "10:50", "review", work_item: item.("ACME-101"))
span.(yesterday, "10:50", "11:05", "review", work_item: item.("ACME-102"))
span.(yesterday, "11:30", "11:55", "qa", work_item: item.("ACME-103"))
span.(yesterday, "13:10", "13:30", "supervision", batch: acme_batch)        # fixing a shared CI break
span.(yesterday, "13:30", "14:10", "review", work_item: item.("ACME-104"))
span.(yesterday, "14:15", "14:40", "qa", work_item: item.("ACME-103"))     # re-checking the rework
span.(yesterday, "15:00", "15:20", "review", work_item: item.("ACME-105"))

# --- Today: smaller batch, one ticket unsized (shows the fallback rule) ----
beacon = { source: "ai-dev-factory", repo: "twinsun-demo/beacon-api", batch: "beacon-today", batch_label: "Beacon batch", date: today, reviewer: me }
run_ticket!(**beacon, key: "BEACON-21", summary: "Rate-limit the public webhooks endpoint", points: 2, start: "09:10", plan_cost: 0.35, impl_cost: 2.75, impl_minutes: 40, review_at: "10:25", outcome: :approved)
run_ticket!(**beacon, key: "BEACON-22", summary: "Add retry with backoff to the sync worker", points: 3, start: "09:10", plan_cost: 0.44, impl_cost: 3.90, impl_minutes: 60, review_at: "11:40", outcome: :approved)
run_ticket!(**beacon, key: "BEACON-23", summary: "Spike: evaluate queue options", points: nil, start: "09:11", plan_cost: 0.29, impl_cost: 1.60, impl_minutes: 35, review_at: "11:50", outcome: :approved)

beacon_batch = Batch.find_by!(source: "ai-dev-factory", external_id: "beacon-today")
span.(today, "09:00", "09:15", "supervision", batch: beacon_batch)
span.(today, "10:00", "10:25", "review", work_item: item.("BEACON-21"))
span.(today, "10:30", "10:45", "development", work_item: item.("BEACON-22"))  # pairing on a tricky bit

# Pre-build yesterday's drafts and approve one, so the Harvest page has content.
DayAttribution.new(person: dev, date: yesterday).write_drafts!
TimeDraft.for_day(dev, yesterday).joins(:work_item).where(work_items: { jira_key: "ACME-101" }).update_all(status: "approved")

puts "Demo data loaded: #{WorkItem.count} tickets, #{Batch.count} batches, #{AttentionSpan.count} attention spans, #{TimeDraft.count} drafts."
puts "Previous weekday (#{yesterday}) has the full demo day."
