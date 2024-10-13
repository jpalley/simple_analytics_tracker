class CreateHourlyStats < ActiveRecord::Migration[8.0]
  def change
    create_table :hourly_stats do |t|
      t.datetime :hour, null: false
      t.integer  :events_count, default: 0
      t.integer  :unique_people_count, default: 0
      t.integer  :new_people_count, default: 0
      t.timestamps
    end

    add_index :hourly_stats, :hour, unique: true
  end
end
