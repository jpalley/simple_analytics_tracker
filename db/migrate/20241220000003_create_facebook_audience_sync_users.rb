class CreateFacebookAudienceSyncUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :facebook_audience_sync_users do |t|
      t.belongs_to :facebook_audience_sync, null: false, foreign_key: true
      t.string :user_identifier_hash, null: false # Hash of email|phone for uniqueness
      t.string :email_hash # SHA256 hash of email for Facebook
      t.string :phone_hash # SHA256 hash of phone for Facebook
      t.text :original_email # Store original for removal (encrypted in production)
      t.text :original_phone # Store original for removal (encrypted in production)
      t.timestamps
    end

    add_index :facebook_audience_sync_users, [ :facebook_audience_sync_id, :user_identifier_hash ],
              unique: true, name: 'index_fb_audience_sync_users_unique'
    add_index :facebook_audience_sync_users, :user_identifier_hash
  end
end
