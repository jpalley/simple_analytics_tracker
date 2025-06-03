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
    # First, process UTK-based sync (existing functionality - takes precedence)
    process_utk_batch(batch)

    # Then, process email-based sync for records without hubspot_contact_id
    process_email_batch(batch)

    # Update sync timestamp for all processed records
    batch.each do |person|
      person.update_column(:hubspot_synced_at, Time.current) # Update timestamp without touching updated_at
    end
  end

  def process_utk_batch(batch)
    utks = batch.map { |person| person.properties["hubspotutk"] }.compact
    return if utks.empty?

    response = hubspot_client.contacts_by_utk(utks)
    batch.each do |person|
      utk = person.properties["hubspotutk"]
      if utk && response[utk]
        person.properties["hubspot_contact_id"] = response[utk]["vid"]
      end
    end
  end

  def process_email_batch(batch)
    # Only process people who have email but no hubspot_contact_id yet
    people_with_emails = batch.select do |person|
      person.properties["email"].present? && person.properties["hubspot_contact_id"].blank?
    end

    return if people_with_emails.empty?

    emails = people_with_emails.map { |person| person.properties["email"] }.uniq
    existing_contacts = hubspot_client.contacts_by_email(emails)

    # Track created contacts to avoid duplicates
    created_contacts = {}

    people_with_emails.each do |person|
      email = person.properties["email"]

      if existing_contacts[email]
        # Contact exists - link the hubspot_contact_id
        contact_id = existing_contacts[email]["id"] || existing_contacts[email]["hs_object_id"]
        person.properties["hubspot_contact_id"] = contact_id
      elsif created_contacts[email]
        # Contact was already created for this email in this batch
        person.properties["hubspot_contact_id"] = created_contacts[email]
      else
        # Contact doesn't exist and hasn't been created yet - create new contact
        begin
          new_contact = hubspot_client.create_contact(email, person.id, "opensend")
          contact_id = new_contact["id"] || new_contact["hs_object_id"]
          person.properties["hubspot_contact_id"] = contact_id
          created_contacts[email] = contact_id # Track the created contact
        rescue => e
          Rails.logger.error("Failed to create HubSpot contact for email #{email}: #{e.message}")
          # Continue processing other records even if one fails
        end
      end
    end
  end

  def hubspot_client
    @hubspot_client ||= HubspotClient.new
  end
end
