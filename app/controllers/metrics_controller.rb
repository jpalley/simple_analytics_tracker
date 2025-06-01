class MetricsController < AdminController
  def index
    @hourly_stats = HourlyStat.order(hour: :desc).last(24 * 30) # Show last 30 days of stats in reverse chronological order
    @recent_errors = ErrorRequest.recent.limit(20)

    # Calculate error rate statistics
    @total_requests_24h = @hourly_stats.sum(&:total_requests_count)
    @total_errors_24h = @hourly_stats.sum(&:error_4xx_count) + @hourly_stats.sum(&:error_5xx_count)
    @error_rate_24h = @total_requests_24h > 0 ? (@total_errors_24h.to_f / @total_requests_24h * 100).round(2) : 0

    # Most common error codes in last 24 hours
    @common_error_codes = ErrorRequest.where(timestamp: 24.hours.ago..Time.current)
                                     .group(:status_code)
                                     .order("count_status_code desc")
                                     .limit(10)
                                     .count(:status_code)
  end
end
