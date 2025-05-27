require "google/cloud/bigquery"
require "csv"

class GoogleAdsCsvController < ApplicationController
  # Generate a secure random token for the URL - use a fixed seed for consistency
  SECURE_TOKEN = ENV["GOOGLE_ADS_CSV_TOKEN"] || "gads_csv_" + Digest::SHA256.hexdigest("#{Rails.application.secret_key_base}-google-ads-csv")[0..31]

  def hubspot_calls_csv
    # Verify the token matches
    unless params[:token] == SECURE_TOKEN
      render plain: "Not Found", status: 404
      return
    end

    begin
      # Connect to BigQuery using same pattern as FacebookSyncJob
      if Rails.env.development?
        bigquery = Google::Cloud::Bigquery.new(
          project: ENV["GOOGLE_CLOUD_PROJECT"],
          credentials: JSON.parse(ENV["GOOGLE_CLOUD_CREDENTIALS"])
        )
      else
        bigquery = Google::Cloud::Bigquery.new(
          project: ENV["GOOGLE_CLOUD_PROJECT"],
          credentials: JSON.parse(ENV["GOOGLE_CLOUD_CREDENTIALS"].gsub(/(?<!\\)(\\n)/, "").gsub('\n', "n"))
        )
      end

      # Get dataset ID and construct table name
      dataset_id = ENV["BIGQUERY_DATASET"]
      table_name = "#{dataset_id}.hubspot_calls"

      # Query for inbound calls from the last week
      query = <<-SQL
        SELECT
          hs_call_from_number as caller_phone,
          hs_timestamp as call_start_time,
          hs_call_duration,
          hs_call_direction,
          hs_call_disposition,
          hs_createdate as conversion_time
        FROM `#{table_name}`
        WHERE hs_call_direction = 'INBOUND'
          AND hs_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
          AND hs_call_from_number IS NOT NULL
        ORDER BY hs_timestamp DESC
      SQL

      results = bigquery.query(query)

      # Generate CSV content
      csv_string = CSV.generate do |csv|
        # Add the required header rows
        csv << [ "Parameters:TimeZone=UTC", "", "", "", "", "", "", "" ]
        csv << [ "Caller's Phone Number", "Call Start Time", "Conversion Name", "Conversion Time", "Conversion Value", "Conversion Currency", "Ad User Data", "Ad Personalization" ]

        # Add data rows
        results.each do |row|
          # Format timestamps for Google Ads (yyyy-MM-dd HH:mm:ss format)
          call_start_time = row[:call_start_time]&.strftime("%Y-%m-%d %H:%M:%S")
          conversion_time = row[:conversion_time]&.strftime("%Y-%m-%d %H:%M:%S")

          # Only include calls with valid phone numbers and timestamps
          next unless row[:caller_phone] && call_start_time && conversion_time

          csv << [
            row[:caller_phone],           # Caller's Phone Number
            call_start_time,              # Call Start Time
            "Inbound Call",               # Conversion Name
            conversion_time,              # Conversion Time
            "1.00",                       # Conversion Value (default to 1.00)
            "USD",                        # Conversion Currency
            "",                           # Ad User Data (optional)
            ""                            # Ad Personalization (optional)
          ]
        end
      end

      # Set response headers for CSV download
      response.headers["Content-Type"] = "text/csv; charset=utf-8"
      response.headers["Content-Disposition"] = "attachment; filename=\"hubspot_calls_#{Date.current.strftime('%Y%m%d')}.csv\""

      render plain: csv_string

    rescue => e
      ErrorLog.create(
        title: "Google Ads CSV Export Error",
        body: "Error generating CSV: #{e.inspect}"
      )
      render plain: "Internal Server Error", status: 500
    end
  end

  # Class method to get the secure URL
  def self.secure_url
    "/google_ads_csv/#{SECURE_TOKEN}"
  end

  # Class method to get the secure token (useful for debugging/logging)
  def self.secure_token
    SECURE_TOKEN
  end

  # Class method to print the full URL (for console usage)
  def self.print_url
    puts "Google Ads CSV URL: #{secure_url}"
    puts "Token: #{SECURE_TOKEN}"
    secure_url
  end
end
