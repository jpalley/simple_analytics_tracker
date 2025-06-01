class HourlyStatJob < ApplicationJob
  queue_as :default

  def perform
    # Calculate stats for the previous hour
    end_time = Time.current.beginning_of_hour
    start_time = end_time - 1.hour
    hour = start_time

    # Ensure stats for this hour haven't been calculated yet
    unless HourlyStat.exists?(hour: hour)
      # Calculate the number of events in the last hour
      events_count = Event.where(timestamp: start_time...end_time).count

      # Calculate the number of unique people in the last hour
      unique_people_count = Event.where(timestamp: start_time...end_time).distinct.count(:uuid)

      # Calculate the number of new people in the last hour
      new_people_count = Person.where(created_at: start_time...end_time).count

      # Calculate error request counts
      error_requests = ErrorRequest.where(timestamp: start_time...end_time)

      error_4xx_count = error_requests.client_errors.count
      error_5xx_count = error_requests.server_errors.count

      # Specific error code counts
      error_400_count = error_requests.by_status_code(400).count
      error_401_count = error_requests.by_status_code(401).count
      error_403_count = error_requests.by_status_code(403).count
      error_404_count = error_requests.by_status_code(404).count
      error_422_count = error_requests.by_status_code(422).count
      error_500_count = error_requests.by_status_code(500).count
      error_502_count = error_requests.by_status_code(502).count
      error_503_count = error_requests.by_status_code(503).count

      # Get total requests count from cache
      cache_key = "requests_count_#{start_time.to_i}"
      total_requests_count = Rails.cache.read(cache_key) || 0
      Rails.cache.delete(cache_key) # Clean up after reading

      # Create the HourlyStat record
      HourlyStat.create!(
        hour: hour,
        events_count: events_count,
        unique_people_count: unique_people_count,
        new_people_count: new_people_count,
        error_4xx_count: error_4xx_count,
        error_5xx_count: error_5xx_count,
        error_400_count: error_400_count,
        error_401_count: error_401_count,
        error_403_count: error_403_count,
        error_404_count: error_404_count,
        error_422_count: error_422_count,
        error_500_count: error_500_count,
        error_502_count: error_502_count,
        error_503_count: error_503_count,
        total_requests_count: total_requests_count
      )
    end
  end
end
