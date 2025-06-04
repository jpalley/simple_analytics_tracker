class CreateFacebookAudienceSyncHistories < ActiveRecord::Migration[8.0]
  def change
    create_table :facebook_audience_sync_histories do |t|
      t.integer :records_synced, default: 0
      t.text :error_message
      t.belongs_to :facebook_audience_sync, null: false, foreign_key: true
      t.timestamps
    end
  end
end
