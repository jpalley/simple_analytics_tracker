class CreatePeople < ActiveRecord::Migration[8.0]
  def change
    create_table :people, id: false do |t|
      t.string :uuid, primary_key: true
      t.json :initial_params
      t.json :latest_params
      t.json :properties, default: {}
      t.boolean :synced, default: false
      t.datetime :synced_at
      t.timestamps
    end
  end
end
