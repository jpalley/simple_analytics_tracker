module Middleware
  class ErrorTrackingMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      request = Rack::Request.new(env)

      # Track total requests
      increment_request_counter

      status, headers, response = @app.call(env)

      # Track errors if status code indicates an error
      if status >= 400
        begin
          error_message = extract_error_message(response)
          ErrorRequest.track_error(
            ActionDispatch::Request.new(env),
            status,
            error_message
          )
        rescue => e
          Rails.logger.error "Error tracking middleware failed: #{e.message}"
        end
      end

      [ status, headers, response ]
    end

    private

    def increment_request_counter
      # We'll implement a simple counter that gets picked up by the hourly stats job
      Rails.cache.increment("requests_count_#{Time.current.beginning_of_hour.to_i}", 1)
    rescue
      # Fail silently if cache is not available
    end

    def extract_error_message(response)
      return nil unless response.respond_to?(:body)

      # Try to extract error message from response body
      body_content = ""
      response.each { |chunk| body_content += chunk }

      # Try to parse as JSON first
      if body_content.present?
        parsed = JSON.parse(body_content)
        return parsed["error"] || parsed["message"] || parsed["errors"]&.join(", ")
      end

      # Return truncated body content if not JSON
      body_content.truncate(500)
    rescue JSON::ParserError
      body_content.truncate(500)
    rescue
      nil
    end
  end
end
