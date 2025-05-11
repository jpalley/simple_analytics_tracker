class CreateHubspotSyncStatuses < ActiveRecord::Migration[7.0]
  def change
    create_table :hubspot_sync_statuses do |t|
      t.string :object_type, null: false
      t.string :status, null: false
      t.integer :record_count
      t.text :error_message
      t.datetime :synced_at

      t.timestamps
    end

    add_index :hubspot_sync_statuses, :object_type
    add_index :hubspot_sync_statuses, :status
  end
end
