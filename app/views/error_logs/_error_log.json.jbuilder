json.extract! error_log, :id, :title, :body, :created_at, :updated_at
json.url error_log_url(error_log, format: :json)
