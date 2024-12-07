class CreateFacebookSyncs < ActiveRecord::Migration[8.0]
  def change
    create_table :facebook_syncs do |t|
      t.boolean :enabled, default: true
      t.boolean :test_mode, default: false
      t.string :table_name
      t.string :event_name
      t.string :event_value
      t.string :last_counter
      t.string :event_source_url
      t.string :action_source
      t.timestamps
    end
  end
end
