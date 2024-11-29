json.extract! facebook_sync, :id, :table_name, :event_name, :event_value, :last_counter, :created_at, :updated_at
json.url facebook_sync_url(facebook_sync, format: :json)
