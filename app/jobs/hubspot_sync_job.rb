# app/jobs/data_cleanup_job.rb

class HubspotSyncJob < ApplicationJob
  BATCH_SIZE = 100
  REQUESTS_PER_MINUTE = 100
  RATE_LIMIT_DELAY = 60.0 / REQUESTS_PER_MINUTE # Seconds between requests

  def perform
    return if ENV["HUBSPOT_ACCESS_TOKEN"].blank?
    Person.where("hubspot_synced_at IS NULL OR hubspot_synced_at < updated_at")
          .in_batches(of: BATCH_SIZE) do |batch|
      process_batch(batch)
      sleep RATE_LIMIT_DELAY # Wait before processing next batch
    end
  end

  private

  def process_batch(batch)
    utks = batch.map { |person| person.properties["hubspotutk"] }.compact
    return if utks.empty?
    puts "utks: #{utks.inspect}"
    response = hubspot_client.contacts_by_utk(utks)
    puts response.inspect
    batch.each do |person|
      utk = person.properties["hubspotutk"]
      if utk && response[utk]
        person.properties["hubspot_contact_id"] = response[utk]["vid"]
      end
      person.hubspot_synced_at = Time.current
      person.save!
    end
  end


  def hubspot_client
    @hubspot_client ||= HubspotClient.new
  end
end
