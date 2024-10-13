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

      # Create the HourlyStat record
      HourlyStat.create!(
        hour: hour,
        events_count: events_count,
        unique_people_count: unique_people_count,
        new_people_count: new_people_count
      )
    end
  end
end
