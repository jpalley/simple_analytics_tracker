class UpdateFacebookAudienceSyncUsersForHubspotId < ActiveRecord::Migration[8.0]
  def change
    # Add HubSpot contact ID column if it doesn't exist
    unless column_exists?(:facebook_audience_sync_users, :hubspot_contact_id)
      add_column :facebook_audience_sync_users, :hubspot_contact_id, :string
    end

    # Remove old indexes if they exist
    if index_exists?(:facebook_audience_sync_users, [ :facebook_audience_sync_id, :user_identifier_hash ], name: "index_fb_audience_sync_users_unique")
      remove_index :facebook_audience_sync_users, name: "index_fb_audience_sync_users_unique"
    end

    if index_exists?(:facebook_audience_sync_users, :user_identifier_hash)
      remove_index :facebook_audience_sync_users, :user_identifier_hash
    end

    # Remove old columns if they exist
    if column_exists?(:facebook_audience_sync_users, :user_identifier_hash)
      remove_column :facebook_audience_sync_users, :user_identifier_hash, :string
    end

    if column_exists?(:facebook_audience_sync_users, :original_email)
      remove_column :facebook_audience_sync_users, :original_email, :text
    end

    if column_exists?(:facebook_audience_sync_users, :original_phone)
      remove_column :facebook_audience_sync_users, :original_phone, :text
    end

    # Make hubspot_contact_id non-null (only if we have no data or add default values)
    # For now, we'll leave it nullable since we're changing the data structure
    # change_column_null :facebook_audience_sync_users, :hubspot_contact_id, false

    # Add new indexes
    unless index_exists?(:facebook_audience_sync_users, [ :facebook_audience_sync_id, :hubspot_contact_id ])
      add_index :facebook_audience_sync_users, [ :facebook_audience_sync_id, :hubspot_contact_id ],
                unique: true, name: 'index_fb_audience_sync_users_hubspot_unique'
    end

    unless index_exists?(:facebook_audience_sync_users, :hubspot_contact_id)
      add_index :facebook_audience_sync_users, :hubspot_contact_id
    end
  end
end
