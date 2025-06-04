class CreateFacebookAudienceSyncs < ActiveRecord::Migration[8.0]
  def change
    create_table :facebook_audience_syncs do |t|
      t.string :table_name, null: false
      t.string :audience_name, null: false
      t.string :facebook_audience_id
      t.string :last_counter, default: "0"
      t.boolean :enabled, default: true
      t.boolean :test_mode, default: false
      t.text :description
      t.timestamps
    end

    add_index :facebook_audience_syncs, :table_name
    add_index :facebook_audience_syncs, :enabled
  end
end
