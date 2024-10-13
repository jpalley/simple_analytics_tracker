class CreateEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :events do |t|
      t.string :uuid
      t.string :event_type
      t.datetime :timestamp
      t.json :event_data
      t.boolean :synced, default: false
      t.datetime :synced_at
      t.timestamps
    end

    add_index :events, :uuid
    add_foreign_key :events, :people, column: :uuid, primary_key: :uuid
  end
end
