class AddIndexesForSyncs < ActiveRecord::Migration[8.0]
  def change
    add_index :people, :hubspot_synced_at
    add_index :people, :synced_at
    add_index :people, :synced
    add_index :events, :synced
    add_index :events, :synced_at
  end
end
