class AddFieldsToFacebookSync < ActiveRecord::Migration[8.0]
  def change
    add_column :facebook_syncs, :event_source_url, :string
    add_column :facebook_syncs, :action_source, :string
    add_column :facebook_syncs, :enabled, :boolean, default: true
    add_column :facebook_syncs, :test_mode, :boolean, default: false
  end
end
