class ErrorRequest < ApplicationRecord
  validates :status_code, presence: true
  validates :request_method, presence: true
  validates :path, presence: true
  validates :timestamp, presence: true

  scope :by_status_code, ->(code) { where(status_code: code) }
  scope :client_errors, -> { where(status_code: 400..499) }
  scope :server_errors, -> { where(status_code: 500..599) }
  scope :within_hour, ->(hour) { where(timestamp: hour..(hour + 1.hour)) }
  scope :recent, -> { order(timestamp: :desc) }

  def self.track_error(request, response_status, error_message = nil)
    create!(
      status_code: response_status,
      request_method: request.request_method,
      path: request.path,
      user_agent: request.user_agent,
      ip_address: request.remote_ip,
      referer: request.referer,
      error_message: error_message,
      request_params: sanitize_params(request.params),
      timestamp: Time.current
    )
  rescue => e
    # Don't let error tracking itself cause issues
    Rails.logger.error "Failed to track error request: #{e.message}"
  end

  private

  def self.sanitize_params(params)
    # Remove sensitive parameters and limit size
    safe_params = params.except("password", "password_confirmation", "token", "authenticity_token")
    safe_params.to_json.truncate(1000)
  rescue
    "{}"
  end
end
