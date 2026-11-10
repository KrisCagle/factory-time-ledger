# Foreman integration: the person's sign-in token (from Foreman's command-line
# sign-in, at most 12 hours, read-only use), and what Foreman says about each
# ticket's process: its inferred run's steps and, where it exists, its timeline.
class AddForemanConnection < ActiveRecord::Migration[8.0]
  def change
    change_table :ledger_settings, bulk: true do |t|
      t.text :foreman_token
      t.string :foreman_token_id
      t.datetime :foreman_token_expires_at
      t.string :foreman_email
      t.string :foreman_name
      t.string :foreman_surface
      t.jsonb :foreman_scopes, null: false, default: []
      t.text :foreman_pending_verifier
      t.string :foreman_pending_state
      t.datetime :foreman_last_synced_at
      t.text :foreman_last_sync_summary
      t.text :foreman_sync_error
    end

    create_table :foreman_runs do |t|
      t.references :work_item, null: false, foreign_key: true, index: { unique: true }
      t.string :run_id
      t.boolean :followed, null: false, default: true
      t.string :workflow
      t.string :workflow_version
      t.string :client
      t.string :position
      t.string :status
      t.string :state
      t.boolean :dormant, null: false, default: false
      t.jsonb :tasks, null: false, default: []
      t.jsonb :timeline, null: false, default: []
      t.datetime :run_started_at
      t.datetime :run_ended_at
      t.datetime :foreman_built_at
      t.datetime :fetched_at
      t.timestamps
    end
  end
end
