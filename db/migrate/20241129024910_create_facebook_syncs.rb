class CreateFacebookSyncs < ActiveRecord::Migration[8.0]
  def change
    create_table :facebook_syncs do |t|
      t.string :table_name
      t.string :event_name
      t.string :event_value
      t.string :last_counter
      t.timestamps
    end
  end
end
