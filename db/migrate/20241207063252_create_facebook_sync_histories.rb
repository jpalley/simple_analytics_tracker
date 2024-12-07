class CreateFacebookSyncHistories < ActiveRecord::Migration[8.0]
  def change
    create_table :facebook_sync_histories do |t|
      t.integer :conversions
      t.belongs_to :facebook_sync
      t.timestamps
    end
  end
end
