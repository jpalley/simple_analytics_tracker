# app/jobs/data_cleanup_job.rb

class DataCleanupJob < ApplicationJob
  def perform
    cutoff_date = 7.days.ago

    # Delete Events
    Event.where("synced = ? AND synced_at <= ?", true, cutoff_date).destroy_all
  end
end
