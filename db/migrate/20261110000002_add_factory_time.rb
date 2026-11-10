# Factory time: the factory's working time on each ticket becomes time on the
# person's draft for that ticket (Attribution::FactoryTime).
class AddFactoryTime < ActiveRecord::Migration[8.0]
  def change
    add_column :time_drafts, :factory_seconds, :integer, null: false, default: 0
    change_table :ledger_settings, bulk: true do |t|
      t.string :factory_time_mode, null: false, default: "shared" # shared | full | off
      t.string :factory_time_activity, null: false, default: "development"
    end
  end
end
