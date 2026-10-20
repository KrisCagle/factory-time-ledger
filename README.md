# Factory Time Ledger

Logs human time to Harvest per ticket automatically, even when an AI factory works a batch of tickets at once.

- **Direct time** (reviewing or QAing a ticket) goes straight to that ticket.
- **Batch overhead** (kicking off a batch, fixing a shared CI break) is pooled and split across the batch's tickets by agent points, agent time, or evenly.
- **Agent time and cost** are tracked per ticket for margin and efficiency reporting. They are never billed.
- Entries are built as **drafts** you review and approve. Nothing reaches Harvest until you send it, and it runs in **dry-run** until Harvest credentials are added.

It is factory-agnostic. Events use [Scarif](https://github.com/twinsunllc/scarif-web)'s vocabulary (work items keyed by Jira key, Scarif's `event_type` names, agent runs with cost), so ai-dev-factory, Scarif, and local Claude Code can all report into it.

## Run it locally

Requirements: Ruby 3.2+, Bundler, and Docker Desktop (running).

```bash
git clone https://github.com/KrisCagle/factory-time-ledger.git
cd factory-time-ledger
bin/setup            # installs gems, starts Postgres in Docker, builds the database, loads demo data
bin/dev              # starts the app on port 3001
```

Open http://localhost:3001. To use a different port: `PORT=4000 bin/dev`.

The app's database runs in Docker on port **5434**, so it won't clash with Scarif's or any other Postgres on 5432. `bin/setup` starts it for you and resets the development database each time, so re-run it whenever you want fresh demo data.

**Prefer your own Postgres?** In `.env`, set `DB_USER`, `DB_PASSWORD` and `DB_PORT` to match it, set `USE_DOCKER_DB=false`, then run `bin/setup`.

## Click-through tour (demo data)

The demo is dated relative to today. The **previous weekday** has a full day; **today** has a morning.

1. **Today** → click **← Prev**. You'll see a timeline of the demo developer's day: green blocks on tickets, amber blocks of batch overhead, grey unattributed time. The table shows each ticket's direct time plus its share of overhead.
2. **Batches** → *Acme morning batch*. See how 40 minutes of overhead splits across five tickets by agent points (ACME-103, at 5 points, takes the biggest share). Open *Beacon batch*: one ticket is unsized, so the split falls back to agent time.
3. **Tickets** → *ACME-103*. Human time vs. agent time and cost, one rework loop, and the full pipeline timeline.
4. **Harvest drafts** → **← Prev**. Drafts for the day, one already approved. Edit hours or notes, approve, then **Send approved (dry run)** and expand *Payload* to see exactly what would be posted. Beacon tickets show *Not mapped* because that project has no Harvest IDs yet.
5. **Settings**. Change the split rule and watch the Batches and Today pages change. The Harvest connection card walks through going live.
6. On **Today** or any ticket, use **Track active time → Start working**. Heartbeats every 30 seconds (paused when the tab is hidden or you've been idle for 2 minutes) build a live attention span. Stop, reload, and it's on the timeline.

## Going live with Harvest

1. Create a personal access token at https://id.getharvest.com/developers. The page also shows your account ID.
2. Put both in `.env` and restart (`bin/dev`):
   ```
   HARVEST_ACCESS_TOKEN=...
   HARVEST_ACCOUNT_ID=...
   ```
3. In **Settings → Harvest connection**, click **Test connection**. It shows the account and person the token belongs to, and whether the account tracks durations or start/end times.
4. Click **Load projects from Harvest**. This pulls in every project you're assigned to, with the tasks assigned to each.
5. In **Projects → Harvest**, pick a Harvest project for each repo. Tasks whose names look like development, QA, and project management are filled in for you; check them, then **Save**.
6. Do one safe test: on a real internal project, track a minute or two with **Start working**, refresh drafts, approve one, and send it. Confirm it in your Harvest timesheet, then delete it there.

### Safety checks

While Harvest is connected, a draft is only sent when:

- **Test connection** has passed, and the account tracks **durations**. Accounts set to start/end times are blocked, since v1 only sends hours; a Harvest admin can switch the account setting.
- The draft's Harvest project is one **loaded from your Harvest**, and its task is **assigned to that project**.

So demo data (which uses made-up Harvest IDs) and mistyped IDs are refused with a clear message instead of landing on the wrong project. Re-run **Load projects from Harvest** whenever your Harvest assignments change.

Entries post as the token's owner. To post for a teammate, the token needs Harvest admin or manager rights and the person needs a Harvest user ID in Settings.

## Sending events from a factory

`POST /api/v1/events` with JSON. Send `{"events": [ ... ]}` to post several at once. Re-sending an event with the same `source` + `event_id` is ignored, so retries are safe.

```json
{
  "source": "ai-dev-factory",
  "event_id": "unique-per-source",
  "event_type": "stage_completed",
  "occurred_at": "2026-10-20T14:05:00-05:00",
  "jira_key": "ACME-101",
  "summary": "Add CSV export",
  "repo": "twinsunllc/acme-portal",
  "batch_id": "batch-2026-10-20-a",
  "batch_label": "Tuesday morning batch",
  "agent_points": 2,
  "person_email": "you@example.com",
  "data": { "stage_id": "st_123", "stage_type": "implement", "cost_usd": 2.10, "tokens": 310000 }
}
```

Required: `source`, `event_id`, `event_type`, `occurred_at`, `jira_key`. Everything else is optional and only needs sending once (on the first event for a ticket is fine).

Event types with side effects:

| event_type | Effect |
|---|---|
| `pipeline_started`, `wait_human_resolved` | Ticket status → in progress |
| `wait_human_entered`, `escalation` | Ticket status → waiting on human |
| `pipeline_completed` / `pipeline_cancelled` | Ticket done / cancelled |
| `stage_claimed` | Starts an agent run (needs `data.stage_id`) |
| `stage_completed`, `stage_failed`, `stage_cancelled` | Ends the run; records `data.cost_usd`, `data.tokens` |
| `agent_points_recorded` | Sets `data.agent_points` |
| `human_review_changes_requested` | Counts as a rework loop |

Any other `event_type` (for example `pr_created`, `pr_merged`, `ci_check`) is stored on the ticket's timeline.

## Sending attention heartbeats

`POST /api/v1/attention` whenever a person is actively working on something, about every 30 seconds:

```json
{ "person_email": "you@example.com", "activity": "review", "jira_key": "ACME-101" }
```

For batch-level work, send `"source"` and `"batch_id"` instead of `jira_key`. `activity` is one of `development`, `review`, `qa`, `supervision`. Heartbeats within the idle limit (Settings, default 3 minutes) extend one span; a longer gap starts a new one.

If `LEDGER_API_TOKEN` is set in `.env`, send it as an `X-Ledger-Token` header. If it's blank, local requests are accepted without one in development.

Quick test from a terminal:

```bash
curl -X POST localhost:3001/api/v1/attention -H 'Content-Type: application/json' \
  -d '{"person_email":"demo.developer@example.com","activity":"review","jira_key":"BEACON-22"}'
```

## How attribution works

The rules live in `lib/attribution/engine.rb`, plain Ruby with no Rails dependency:

1. Attention is single-threaded. If spans overlap, the later one wins.
2. Time on a ticket is direct time for that ticket.
3. Time on a batch is overhead, split across the batch's tickets. Agent points falls back to agent time if any ticket is unsized; agent time falls back to an even split. Splits are in whole seconds and always add back up exactly.
4. Time on neither is unattributed. It's shown on Today but never drafted.

Refreshing drafts re-runs this for the day. Approved and sent drafts are never changed by a refresh.

## Tests

```bash
bin/rails test                                   # everything
ruby -Ilib test/lib/attribution_engine_test.rb   # just the attribution rules, no database needed
```

## Roadmap

- **ai-dev-factory**: post events and attention heartbeats from the factory UI's inbox and review walkthrough.
- **Local Claude Code**: hooks that post events for sessions tied to a Jira key.
- **Scarif**: a read-only adapter for Scarif's work items and pipeline events (no changes to Scarif needed), then optionally Scarif posting events directly and sending attention pings from its ask and review pages.
- Harvest timestamp-mode accounts, per-person views for a team lead, and weekly rollups.
