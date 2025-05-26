class FacebookSyncJob < ApplicationJob
  queue_as :default

  def perform(*args)
    require "facebookbusiness"
    require "google/cloud/bigquery"
    begin
    access_token = ENV["FACEBOOK_TOKEN"]
    pixel_id = ENV["FACEBOOK_PIXEL_ID"]

    FacebookAds.configure do |config|
      config.access_token = access_token
    end

    if Rails.env.development?
      bigquery = Google::Cloud::Bigquery.new(
        project: ENV["GOOGLE_CLOUD_PROJECT"],
      # credentials: JSON.parse(ENV["GOOGLE_CLOUD_CREDENTIALS"].gsub(/(?<!\\)(\\n)/, "").gsub('\n', "n"))
      credentials: JSON.parse(ENV["GOOGLE_CLOUD_CREDENTIALS"])
      )
    else
      bigquery = Google::Cloud::Bigquery.new(
        project: ENV["GOOGLE_CLOUD_PROJECT"],
      credentials: JSON.parse(ENV["GOOGLE_CLOUD_CREDENTIALS"].gsub(/(?<!\\)(\\n)/, "").gsub('\n', "n"))
      # credentials: JSON.parse(ENV["GOOGLE_CLOUD_CREDENTIALS"])
    )
    end

    FacebookSync.where(enabled: true).each do |sync|
      table_name = sync.table_name
      last_counter = sync.last_counter

      # Query BigQuery for conversion data since last_counter
      query = <<-SQL
        SELECT email, phone, user_agent, ip_address, fbc, fbp, row_counter, conversion_time FROM `#{table_name}`

        WHERE row_counter > #{last_counter} ORDER BY row_counter DESC
      SQL

      results = bigquery.query query

      results.each do |row|
        puts row.inspect
        # Extract necessary data from row
        user_data = FacebookAds::ServerSide::UserData.new(
          emails: [ row[:email]&.downcase ],
          phones: [ row[:phone] ],
          client_user_agent: row[:user_agent],
          client_ip_address: row[:ip_address],
          fbc: row[:fbc],
          fbp: row[:fbp]
        )

        # content = FacebookAds::ServerSide::Content.new(
        #   product_id: "product123",
        #   quantity: 1,
        #   delivery_category: "home_delivery"
        # )
        custom_data = FacebookAds::ServerSide::CustomData.new(
          # contents: [ content ],
          currency: "usd",
          value: 123.46 # sync.event_value
        )

        event = FacebookAds::ServerSide::Event.new(
          event_name: sync.event_name,
          event_time: row[:conversion_time],
          event_id: "#{row[:visitor_id]}-#{row[:conversion_time]}",
          user_data: user_data,
          custom_data: custom_data,
          event_source_url: sync.event_source_url,
          action_source: "website"
        )
        if sync.test_mode
          request = FacebookAds::ServerSide::EventRequest.new(
            pixel_id: pixel_id,
            events: [ event ],
            test_event_code: "TEST70628"
          )
        else
          request = FacebookAds::ServerSide::EventRequest.new(
            pixel_id: pixel_id,
            events: [ event ]
          )
        end
        puts request.inspect

        print request.execute
      end

      # Update last_counter
      sync.update(last_counter: results.map { |r| r[:row_counter] }.max) unless results.empty?
      FacebookSyncHistory.create(conversions: results.count, facebook_sync: sync)
      end
    rescue => e
      ErrorLog.create(title: "Facebook Sync Job Error for #{job_id}, Enqueued at: #{enqueued_at}", body: e.inspect)
      raise e
    end
  end
end
