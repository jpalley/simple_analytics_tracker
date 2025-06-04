class FacebookAudienceSyncJob < ApplicationJob
  queue_as :default

  def perform(*args)
    require "facebookbusiness"
    require "google/cloud/bigquery"
    require "digest"

    begin
      # Initialize Facebook Ads API
      access_token = ENV["FACEBOOK_TOKEN"]
      ad_account_id = ENV["FACEBOOK_AD_ACCOUNT_ID"]

      FacebookAds.configure do |config|
        config.access_token = access_token
      end

      # Initialize BigQuery client
      bigquery = initialize_bigquery_client

      # Process all enabled audience syncs
      FacebookAudienceSync.where(enabled: true).each do |sync|
        process_audience_sync(sync, bigquery, ad_account_id)
      end

    rescue => e
      ErrorLog.create(
        title: "Facebook Audience Sync Job Error for #{job_id}, Enqueued at: #{enqueued_at}",
        body: e.inspect
      )
      raise e
    end
  end

  private

  def initialize_bigquery_client
    if Rails.env.development?
      Google::Cloud::Bigquery.new(
        project: ENV["GOOGLE_CLOUD_PROJECT"],
        credentials: JSON.parse(ENV["GOOGLE_CLOUD_CREDENTIALS"])
      )
    else
      Google::Cloud::Bigquery.new(
        project: ENV["GOOGLE_CLOUD_PROJECT"],
        credentials: JSON.parse(ENV["GOOGLE_CLOUD_CREDENTIALS"].gsub(/(?<!\\)(\\n)/, "").gsub('\n', "n"))
      )
    end
  end

  def process_audience_sync(sync, bigquery, ad_account_id)
    history = sync.facebook_audience_sync_histories.create!(records_synced: 0)

    begin
      Rails.logger.info "Processing Facebook Audience Sync: #{sync.id} - #{sync.audience_name}"

      # Get current users from BigQuery
      current_bigquery_users = get_bigquery_users(sync, bigquery)

      if current_bigquery_users.empty?
        Rails.logger.info "No users found in BigQuery table for sync #{sync.id}"
        return
      end

      # Create or get Facebook Custom Audience
      audience = get_or_create_custom_audience(sync, ad_account_id)

      # Get currently tracked users
      currently_synced_users = sync.facebook_audience_sync_users.includes(:facebook_audience_sync)

      # Create sets for comparison using HubSpot contact IDs
      current_hubspot_ids = current_bigquery_users.map { |u| u[:hubspot_contact_id] }.to_set
      synced_hubspot_ids = currently_synced_users.map(&:hubspot_contact_id).to_set

      # Calculate what needs to be added and removed
      users_to_add = current_bigquery_users.select { |u| !synced_hubspot_ids.include?(u[:hubspot_contact_id]) }
      users_to_remove = currently_synced_users.select { |u| !current_hubspot_ids.include?(u.hubspot_contact_id) }

      Rails.logger.info "Sync #{sync.id}: #{users_to_add.size} to add, #{users_to_remove.size} to remove"

      records_processed = 0

      # Add new users to Facebook audience
      if users_to_add.any?
        facebook_data_to_add = users_to_add.map { |u| u[:facebook_data] }
        added_count = sync_users_to_facebook(audience, facebook_data_to_add, :add, sync.test_mode)

        # Track the new users in our database
        users_to_add.each do |user_data|
          FacebookAudienceSyncUser.track_user(sync, user_data[:hubspot_contact_id], user_data[:email], user_data[:phone])
        end

        records_processed += added_count
        Rails.logger.info "Added #{added_count} users to audience #{sync.audience_name}"
      end

      # Remove users from Facebook audience
      if users_to_remove.any?
        facebook_data_to_remove = users_to_remove.map(&:facebook_user_data)
        removed_count = sync_users_to_facebook(audience, facebook_data_to_remove, :remove, sync.test_mode)

        # Remove tracking records
        users_to_remove.each(&:destroy!)

        Rails.logger.info "Removed #{removed_count} users from audience #{sync.audience_name}"
      end

      # Update history with the number of additions (primary metric)
      history.update!(records_synced: records_processed)

      Rails.logger.info "Sync #{sync.id} completed: #{records_processed} records processed"

    rescue => e
      error_message = "Error syncing audience #{sync.audience_name}: #{e.message}"
      Rails.logger.error error_message
      history.update!(error_message: error_message)
      raise e
    end
  end

  def get_bigquery_users(sync, bigquery)
    # Get all current users from BigQuery table - now including HubSpot contact ID
    query = <<-SQL
      SELECT
        hubspot_contact_id,
        email,
        phone
      FROM `#{sync.table_name}`
      WHERE hubspot_contact_id IS NOT NULL
        AND (email IS NOT NULL OR phone IS NOT NULL)
        AND (TRIM(email) != '' OR TRIM(CAST(phone AS STRING)) != '')
    SQL

    results = bigquery.query(query)
    users = []

    results.each do |row|
      hubspot_contact_id = row[:hubspot_contact_id]&.to_s&.strip
      email = row[:email]&.strip
      phone = row[:phone]&.to_s&.strip

      # Skip if no HubSpot contact ID or both email and phone are empty
      next if hubspot_contact_id.blank? || (email.blank? && phone.blank?)

      # Prepare Facebook data
      facebook_data = {}
      facebook_data["EMAIL"] = [ Digest::SHA256.hexdigest(email.downcase) ] if email.present?
      if phone.present?
        cleaned_phone = clean_phone_number(phone)
        facebook_data["PHONE"] = [ Digest::SHA256.hexdigest(cleaned_phone) ] if cleaned_phone.present?
      end

      # Only include if we have valid Facebook data
      next if facebook_data.empty?

      users << {
        hubspot_contact_id: hubspot_contact_id,
        email: email,
        phone: phone,
        facebook_data: facebook_data
      }
    end

    users
  end

  def get_or_create_custom_audience(sync, ad_account_id)
    # If we already have a Facebook audience ID, use it
    if sync.facebook_audience_id.present?
      begin
        audience = FacebookAds::CustomAudience.get(sync.facebook_audience_id)
        return audience if audience
      rescue => e
        Rails.logger.warn "Could not find existing audience #{sync.facebook_audience_id}, creating new one: #{e.message}"
      end
    end

    # Create new Custom Audience
    ad_account = FacebookAds::AdAccount.get("act_#{ad_account_id}")

    audience_params = {
      "name" => sync.audience_name,
      "subtype" => "CUSTOM",
      "description" => sync.description || "Synced from BigQuery table: #{sync.table_name}",
      "customer_file_source" => "USER_PROVIDED_ONLY"
    }

    audience = ad_account.customaudiences.create(audience_params)

    # Store the Facebook audience ID
    sync.update!(facebook_audience_id: audience.id)

    audience
  end

  def clean_phone_number(phone)
    return nil if phone.blank?

    # Remove all non-digit characters
    cleaned = phone.gsub(/\D/, "")

    # Add country code if missing (assuming US)
    cleaned = "1#{cleaned}" if cleaned.length == 10

    # Return only if it looks like a valid phone number
    cleaned.length >= 10 ? cleaned : nil
  end

  def sync_users_to_facebook(audience, user_data_array, operation, test_mode = false)
    return 0 if user_data_array.empty?

    # Facebook allows up to 10,000 users per batch
    batch_size = 10000
    total_processed = 0

    user_data_array.each_slice(batch_size) do |batch|
      if test_mode
        Rails.logger.info "TEST MODE: Would #{operation} #{batch.size} users to/from audience #{audience.id}"
        total_processed += batch.size
      else
        begin
          params = {
            "payload" => {
              "schema" => [ "EMAIL", "PHONE" ],
              "data" => batch
            }
          }

          case operation
          when :add
            result = audience.create_user(params)
          when :remove
            result = audience.delete_user(params)
          end

          total_processed += batch.size
          Rails.logger.info "#{operation.to_s.capitalize}ed batch of #{batch.size} users to/from audience #{audience.id}"

          # Add small delay between batches to avoid rate limits
          sleep(1) if user_data_array.size > batch_size
        rescue => e
          Rails.logger.error "Error #{operation}ing batch to/from Facebook: #{e.message}"
          raise e
        end
      end
    end

    total_processed
  end
end
