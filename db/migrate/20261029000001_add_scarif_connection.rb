# Scarif integration: remembers each Scarif work item the ledger has read, so a
# sync only re-reads items that changed, and the token owner and sync status.
class AddScarifConnection < ActiveRecord::Migration[8.0]
  def change
    create_table :external_records do |t|
      t.string :source, null: false
      t.string :external_id, null: false
      t.references :work_item, foreign_key: true
      t.string :jira_key
      t.string :enqueued_by_id
      t.datetime :external_created_at
      t.datetime :external_updated_at
      t.timestamps
    end
    add_index :external_records, %i[source external_id], unique: true

    change_table :ledger_settings, bulk: true do |t|
      t.string :scarif_user_id
      t.string :scarif_user_name
      t.string :scarif_user_email
      t.jsonb :scarif_token_scopes, null: false, default: []
      t.datetime :scarif_checked_at
      t.text :scarif_check_error
      t.datetime :scarif_last_synced_at
      t.text :scarif_last_sync_summary
      t.text :scarif_sync_error
      t.boolean :scarif_only_mine, null: false, default: true
      t.integer :scarif_lookback_days, null: false, default: 14
    end
  end
end
