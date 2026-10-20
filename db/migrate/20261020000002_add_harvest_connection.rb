# Caches what the Harvest token can see, so Settings can offer real projects
# and tasks to pick from and sends can be checked against them.
class AddHarvestConnection < ActiveRecord::Migration[8.0]
  def change
    create_table :harvest_projects do |t|
      t.bigint :harvest_id, null: false
      t.string :name, null: false
      t.string :code
      t.string :client_name
      t.boolean :is_active, null: false, default: true
      t.jsonb :tasks, null: false, default: [] # [{ "id" => 123, "name" => "Development", "billable" => true }]
      t.timestamps
    end
    add_index :harvest_projects, :harvest_id, unique: true

    change_table :ledger_settings, bulk: true do |t|
      t.string :harvest_account_name
      t.bigint :harvest_user_id
      t.string :harvest_user_name
      t.string :harvest_user_email
      t.boolean :harvest_timestamp_mode
      t.datetime :harvest_checked_at
      t.text :harvest_check_error
      t.datetime :harvest_projects_synced_at
    end
  end
end
