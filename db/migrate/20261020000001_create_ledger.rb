# One migration for the whole v1 schema. Names deliberately follow Scarif's
# vocabulary (work items keyed by Jira key, pipeline events with Scarif's
# event_type names, agent runs with cost) so a Scarif adapter can map its rows
# across with little translation.
class CreateLedger < ActiveRecord::Migration[8.0]
  def change
    create_table :people do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.bigint :harvest_user_id
      t.timestamps
    end
    add_index :people, :email, unique: true

    # Maps a repository to the Harvest project and tasks its time is logged to.
    create_table :projects do |t|
      t.string :repo, null: false
      t.string :name, null: false
      t.bigint :harvest_project_id
      t.bigint :harvest_dev_task_id
      t.bigint :harvest_qa_task_id
      t.bigint :harvest_supervision_task_id
      t.timestamps
    end
    add_index :projects, :repo, unique: true

    # A group of tickets put into a factory together.
    create_table :batches do |t|
      t.string :source, null: false
      t.string :external_id, null: false
      t.string :label
      t.references :started_by, foreign_key: { to_table: :people }
      t.datetime :started_at, null: false
      t.timestamps
    end
    add_index :batches, %i[source external_id], unique: true

    create_table :work_items do |t|
      t.string :jira_key, null: false
      t.string :summary
      t.string :source, null: false
      t.references :project, foreign_key: true
      t.references :batch, foreign_key: true
      t.integer :agent_points
      t.string :status, null: false, default: "queued"
      t.datetime :enqueued_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :work_items, :jira_key, unique: true

    # Append-only timeline. (source, external_id) makes re-sent events harmless.
    create_table :pipeline_events do |t|
      t.references :work_item, null: false, foreign_key: true
      t.references :person, foreign_key: true
      t.string :source, null: false
      t.string :external_id, null: false
      t.string :event_type, null: false
      t.datetime :occurred_at, null: false
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end
    add_index :pipeline_events, %i[source external_id], unique: true
    add_index :pipeline_events, %i[work_item_id occurred_at]

    # One agent stage run (Scarif: a stage / factory node run).
    create_table :agent_runs do |t|
      t.references :work_item, null: false, foreign_key: true
      t.string :source, null: false
      t.string :external_id, null: false
      t.string :stage_type
      t.datetime :started_at
      t.datetime :completed_at
      t.decimal :cost_usd, precision: 12, scale: 6
      t.integer :tokens
      t.timestamps
    end
    add_index :agent_runs, %i[source external_id], unique: true

    # Active human time. Heartbeats extend the open span; a gap longer than
    # the idle limit starts a new one.
    create_table :attention_spans do |t|
      t.references :person, null: false, foreign_key: true
      t.references :work_item, foreign_key: true
      t.references :batch, foreign_key: true
      t.string :activity, null: false
      t.string :source, null: false, default: "heartbeat"
      t.datetime :started_at, null: false
      t.datetime :last_seen_at, null: false
      t.timestamps
    end
    add_index :attention_spans, %i[person_id started_at]

    # What the app proposes to log to Harvest. Lives here until approved,
    # because Harvest itself has no draft state for time entries.
    create_table :time_drafts do |t|
      t.references :person, null: false, foreign_key: true
      t.references :work_item, null: false, foreign_key: true
      t.date :spent_on, null: false
      t.string :activity, null: false
      t.integer :direct_seconds, null: false, default: 0
      t.integer :overhead_seconds, null: false, default: 0
      t.decimal :hours, precision: 6, scale: 2, null: false
      t.text :notes
      t.string :status, null: false, default: "draft"
      t.bigint :harvest_time_entry_id
      t.datetime :sent_at
      t.text :last_error
      t.jsonb :last_payload
      t.timestamps
    end
    add_index :time_drafts, %i[person_id work_item_id spent_on activity], unique: true, name: "index_time_drafts_uniqueness"

    create_table :ledger_settings do |t|
      t.string :split_rule, null: false, default: "agent_points"
      t.integer :idle_gap_minutes, null: false, default: 3
      t.integer :rounding_minutes, null: false, default: 1
      t.timestamps
    end
  end
end
