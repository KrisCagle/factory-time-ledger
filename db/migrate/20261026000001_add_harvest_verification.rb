class AddHarvestVerification < ActiveRecord::Migration[8.0]
  def change
    change_table :time_drafts, bulk: true do |t|
      t.datetime :harvest_verified_at
      t.text :harvest_verify_note
    end

    change_table :ledger_settings, bulk: true do |t|
      t.datetime :harvest_test_passed_at
      t.jsonb :harvest_test_log, null: false, default: []
    end
  end
end
