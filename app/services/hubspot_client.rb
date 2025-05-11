class HubspotClient
  require "hubspot-api-client"
  require "ostruct"

  SUPPORTED_OBJECTS = [
    :contacts,
    :companies,
    :deals,
    :owners,
    :tickets,
    :engagements,
    :deal_pipelines,
    :deal_stages,
    :line_items,
    :products,
    :workflows,
    :properties,
    :lists,
    :call_records,
    :meetings
  ]

  # Rate limits for different types of endpoints
  RATE_LIMITS = {
    default: { limit: 100, window: 10 }, # 100 requests per 10 seconds for most endpoints
    workflows: { limit: 50, window: 10 }, # More conservative rate for workflows
    properties: { limit: 100, window: 10 },
    lists: { limit: 30, window: 10 },     # Lists API has stricter limits
    calls: { limit: 40, window: 10 },
    meetings: { limit: 50, window: 10 }
  }

  def initialize
    @client = ::Hubspot::Client.new(access_token: ENV["HUBSPOT_ACCESS_TOKEN"])
    @rate_limit_managers = {}

    # Initialize rate limit managers for each endpoint type
    RATE_LIMITS.each do |endpoint_type, config|
      @rate_limit_managers[endpoint_type] = RateLimitManager.new(config[:limit], config[:window])
    end
  end

  def contacts_by_utk(utks)
    utks = utks.map { |u| "utk=#{u}" }.join("&")
    response = HTTParty.get("https://api.hubapi.com/contacts/v1/contact/byUtk/batch/?#{utks}", {
      headers: {
        "Authorization" => "Bearer #{ENV['HUBSPOT_ACCESS_TOKEN']}"
      }
    })
    raise "Hubspot API Error: #{response.parsed_response.inspect}" if !response.success?
    return {} unless response.success?

    # Convert response to a hash with utk as keys for easier lookup
    result = {}
    response.parsed_response.each do |utk, contact|
      if contact["is-contact"] == true
        result[utk] = contact
      end
    end
    result
  end

  def get_contacts(limit: 100, after: nil, updated_after: nil)
    with_rate_limiting(:default) do
      if updated_after
        # Use search endpoint with updated timestamp filter
        filter = {
          propertyName: "lastmodifieddate",
          operator: "GTE",
          value: updated_after
        }
        response = @client.crm.contacts.search_api.do_search({
          limit: limit,
          after: after,
          filters: [ filter ],
          sorts: [ { propertyName: "lastmodifieddate", direction: "ASCENDING" } ],
          properties: [ "*" ] # Fetch all properties
        })
      else
        # Standard pagination with all properties
        response = @client.crm.contacts.basic_api.get_page(
          limit: limit,
          after: after,
          properties: [ "*" ] # Fetch all properties
        )
      end
      normalize_response(response)
    end
  end

  def get_companies(limit: 100, after: nil, updated_after: nil)
    with_rate_limiting(:default) do
      if updated_after
        # Use search endpoint with updated timestamp filter
        filter = {
          propertyName: "hs_lastmodifieddate",
          operator: "GTE",
          value: updated_after
        }
        response = @client.crm.companies.search_api.do_search({
          limit: limit,
          after: after,
          filters: [ filter ],
          sorts: [ { propertyName: "hs_lastmodifieddate", direction: "ASCENDING" } ],
          properties: [ "*" ] # Fetch all properties
        })
      else
        # Standard pagination with all properties
        response = @client.crm.companies.basic_api.get_page(
          limit: limit,
          after: after,
          properties: [ "*" ] # Fetch all properties
        )
      end
      normalize_response(response)
    end
  end

  def get_deals(limit: 100, after: nil, updated_after: nil)
    with_rate_limiting(:default) do
      if updated_after
        # Use search endpoint with updated timestamp filter
        filter = {
          propertyName: "hs_lastmodifieddate",
          operator: "GTE",
          value: updated_after
        }
        response = @client.crm.deals.search_api.do_search({
          limit: limit,
          after: after,
          filters: [ filter ],
          sorts: [ { propertyName: "hs_lastmodifieddate", direction: "ASCENDING" } ],
          properties: [ "*" ] # Fetch all properties
        })
      else
        # Standard pagination with all properties
        response = @client.crm.deals.basic_api.get_page(
          limit: limit,
          after: after,
          properties: [ "*" ] # Fetch all properties
        )
      end
      normalize_response(response)
    end
  end

  def get_tickets(limit: 100, after: nil, updated_after: nil)
    with_rate_limiting(:default) do
      if updated_after
        # Use search endpoint with updated timestamp filter
        filter = {
          propertyName: "hs_lastmodifieddate",
          operator: "GTE",
          value: updated_after
        }
        response = @client.crm.tickets.search_api.do_search({
          limit: limit,
          after: after,
          filters: [ filter ],
          sorts: [ { propertyName: "hs_lastmodifieddate", direction: "ASCENDING" } ],
          properties: [ "*" ] # Fetch all properties
        })
      else
        # Standard pagination with all properties
        response = @client.crm.tickets.basic_api.get_page(
          limit: limit,
          after: after,
          properties: [ "*" ] # Fetch all properties
        )
      end
      normalize_response(response)
    end
  end

  def get_owners(limit: 100, after: nil)
    with_rate_limiting(:default) do
      response = @client.crm.owners.owners_api.get_page(limit: limit, after: after)
      normalize_response(response)
    end
  end

  def get_deal_pipelines
    with_rate_limiting(:default) do
      @client.crm.pipelines.pipelines_api.get_all(object_type: "deals")
    end
  end

  def get_deal_stages
    with_rate_limiting(:default) do
      # This endpoint gets all pipelines with their stages
      pipelines = @client.crm.pipelines.pipelines_api.get_all(object_type: "deals")

      # Extract all stages from all pipelines
      stages = []
      pipelines.results.each do |pipeline|
        if pipeline.stages
          pipeline.stages.each do |stage|
            stage_data = stage.to_hash
            stage_data[:pipeline_id] = pipeline.id
            stage_data[:pipeline_label] = pipeline.label
            stages << stage_data
          end
        end
      end

      # Return a structure similar to other endpoints
      OpenStruct.new(results: stages)
    end
  end

  def get_engagements(limit: 100, offset: 0)
    with_rate_limiting(:default) do
      # Using the legacy engagements API as it's not fully available in the CRM API
      response = HTTParty.get("https://api.hubapi.com/engagements/v1/engagements/paged?limit=#{limit}&offset=#{offset}", {
        headers: {
          "Authorization" => "Bearer #{ENV['HUBSPOT_ACCESS_TOKEN']}"
        }
      })
      raise "Hubspot API Error: #{response.parsed_response.inspect}" if !response.success?
      response.parsed_response
    end
  end

  def get_line_items(limit: 100, after: nil)
    with_rate_limiting(:default) do
      response = @client.crm.line_items.basic_api.get_page(limit: limit, after: after)
      normalize_response(response)
    end
  end

  def get_products(limit: 100, after: nil)
    with_rate_limiting(:default) do
      response = @client.crm.products.basic_api.get_page(limit: limit, after: after)
      normalize_response(response)
    end
  end

  # New methods for additional objects

  def get_workflows(limit: 50, offset: 0)
    with_rate_limiting(:workflows) do
      response = HTTParty.get("https://api.hubapi.com/automation/v3/workflows?limit=#{limit}&offset=#{offset}", {
        headers: {
          "Authorization" => "Bearer #{ENV['HUBSPOT_ACCESS_TOKEN']}"
        }
      })
      raise "Hubspot API Error: #{response.parsed_response.inspect}" if !response.success?

      # Transform to match our standard format
      results = response.parsed_response["workflows"] || []
      OpenStruct.new(
        results: results,
        paging: response.parsed_response["paging"] ?
          OpenStruct.new(
            next: OpenStruct.new(
              after: response.parsed_response["paging"]["next"]["offset"].to_s
            )
          ) : nil
      )
    end
  end

  def get_properties(object_type: "contacts", archived: false)
    with_rate_limiting(:properties) do
      # Object type can be contacts, companies, deals, tickets, etc.
      response = HTTParty.get("https://api.hubapi.com/properties/v2/#{object_type}/properties?archived=#{archived}", {
        headers: {
          "Authorization" => "Bearer #{ENV['HUBSPOT_ACCESS_TOKEN']}"
        }
      })
      raise "Hubspot API Error: #{response.parsed_response.inspect}" if !response.success?

      # Transform to match our standard format
      OpenStruct.new(
        results: response.parsed_response,
        paging: nil  # Properties API doesn't have pagination
      )
    end
  end

  def get_lists(limit: 30, offset: 0, list_type: "static")
    with_rate_limiting(:lists) do
      # list_type can be 'static' or 'dynamic'
      response = HTTParty.get("https://api.hubapi.com/contacts/v1/lists?count=#{limit}&offset=#{offset}&list_type=#{list_type}", {
        headers: {
          "Authorization" => "Bearer #{ENV['HUBSPOT_ACCESS_TOKEN']}"
        }
      })
      raise "Hubspot API Error: #{response.parsed_response.inspect}" if !response.success?

      # Lists API uses different pagination parameters
      has_more = response.parsed_response["has-more"] || false
      offset = response.parsed_response["offset"] if has_more

      # Transform to match our standard format
      OpenStruct.new(
        results: response.parsed_response["lists"] || [],
        paging: has_more ?
          OpenStruct.new(
            next: OpenStruct.new(
              after: offset.to_s
            )
          ) : nil,
        hasMore: has_more
      )
    end
  end

  def get_call_records(limit: 40, offset: 0)
    with_rate_limiting(:calls) do
      response = HTTParty.get("https://api.hubapi.com/calling/v1/calls?limit=#{limit}&offset=#{offset}", {
        headers: {
          "Authorization" => "Bearer #{ENV['HUBSPOT_ACCESS_TOKEN']}"
        }
      })
      raise "Hubspot API Error: #{response.parsed_response.inspect}" if !response.success?

      # Transform to match our standard format
      results = response.parsed_response["results"] || []
      has_more = response.parsed_response["hasMore"] || false
      offset = response.parsed_response["offset"] if has_more

      OpenStruct.new(
        results: results,
        paging: has_more ?
          OpenStruct.new(
            next: OpenStruct.new(
              after: offset.to_s
            )
          ) : nil,
        hasMore: has_more
      )
    end
  end

  def get_meetings(limit: 50, after: nil, updated_after: nil)
    with_rate_limiting(:meetings) do
      # Using the CRM API for meetings
      url = "https://api.hubapi.com/crm/v3/objects/meetings?limit=#{limit}"
      url += "&after=#{after}" if after
      # Add hs_lastmodifieddate filter for incremental sync
      if updated_after
        # Convert ISO8601 string to millisecond timestamp for Hubspot
        timestamp = Time.parse(updated_after).to_i * 1000
        url += "&filterGroups=[{\"filters\":[{\"propertyName\":\"hs_lastmodifieddate\",\"operator\":\"GTE\",\"value\":#{timestamp}}]}]"
      end

      # Add all properties
      url += "&properties=*"

      response = HTTParty.get(url, {
        headers: {
          "Authorization" => "Bearer #{ENV['HUBSPOT_ACCESS_TOKEN']}"
        }
      })
      raise "Hubspot API Error: #{response.parsed_response.inspect}" if !response.success?

      # Transform to match our standard format
      results = response.parsed_response["results"] || []
      paging = response.parsed_response["paging"] ?
        normalize_paging(response.parsed_response["paging"]) : nil

      OpenStruct.new(
        results: results,
        paging: paging
      )
    end
  end

  private

  def normalize_response(response)
    return response if !response.respond_to?(:paging)

    # Create a new OpenStruct with the same data but normalized paging
    OpenStruct.new(
      results: response.results,
      paging: normalize_paging(response.paging)
    )
  end

  def normalize_paging(paging)
    return nil if paging.nil?

    # Handle different paging formats
    after = nil
    if paging.respond_to?(:_next) && paging._next && paging._next.respond_to?(:after)
      after = paging._next.after
    elsif paging.respond_to?(:next) && paging.next && paging.next.respond_to?(:after)
      after = paging.next.after
    elsif paging.is_a?(Hash) && paging["next"] && paging["next"]["after"]
      after = paging["next"]["after"]
    end

    # Create a consistent paging structure with a 'next' object that has an 'after' property
    OpenStruct.new(
      next: OpenStruct.new(
        after: after
      )
    )
  end

  def with_rate_limiting(endpoint_type = :default)
    manager = @rate_limit_managers[endpoint_type] || @rate_limit_managers[:default]
    manager.wait_if_needed
    response = yield
    manager.record_request
    response
  rescue => e
    if e.message.include?("too many requests") || (e.respond_to?(:response) && e.response&.code == 429)
      Rails.logger.warn("Hubspot rate limit hit for #{endpoint_type}, retrying after delay")
      sleep(10)
      retry
    else
      raise e
    end
  end

  class RateLimitManager
    # Default: 100 requests per 10 seconds
    def initialize(rate_limit = 100, time_window = 10)
      @rate_limit = rate_limit
      @time_window = time_window  # seconds
      @request_timestamps = []
    end

    def record_request
      now = Time.now
      # Add current timestamp
      @request_timestamps << now
      # Clean up old timestamps
      @request_timestamps.reject! { |t| t < now - @time_window }
    end

    def wait_if_needed
      now = Time.now
      # Clean up old timestamps
      @request_timestamps.reject! { |t| t < now - @time_window }

      # Check if we're at the limit
      if @request_timestamps.size >= @rate_limit
        # Calculate how long we need to wait
        oldest = @request_timestamps.min
        wait_time = @time_window - (now - oldest)

        if wait_time > 0
          Rails.logger.info("Rate limiting - waiting #{wait_time.round(2)} seconds")
          sleep(wait_time)
        end
      end
    end
  end
end
