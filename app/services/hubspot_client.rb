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
    :calls,
    :emails,
    :meetings,
    :notes,
    :leads
  ]

  # Rate limits for different types of endpoints
  RATE_LIMITS = {
    default: { limit: 150, window: 10 }, # 150 requests per 10 seconds for most endpoints
    search: { limit: 50, window: 10 },  # Search endpoints limited to 5 requests per second
    workflows: { limit: 50, window: 10 }, # More conservative rate for workflows
    properties: { limit: 100, window: 10 },
    lists: { limit: 30, window: 10 },     # Lists API has stricter limits
    calls: { limit: 40, window: 10 },
    emails: { limit: 40, window: 10 },
    meetings: { limit: 50, window: 10 },
    notes: { limit: 40, window: 10 },
    leads: { limit: 100, window: 10 }
  }

  def initialize
    @client = ::Hubspot::Client.new(access_token: ENV["HUBSPOT_ACCESS_TOKEN"])
    @rate_limit_managers = {}
    @property_cache = {}

    # Initialize rate limit managers for each endpoint type
    RATE_LIMITS.each do |endpoint_type, config|
      @rate_limit_managers[endpoint_type] = RateLimitManager.new(config[:limit], config[:window])
    end
  end

  # Get all property definitions for a given object type
  def get_all_property_definitions(object_type)
    # Return from cache if available
    return @property_cache[object_type.to_s] if @property_cache[object_type.to_s]

    # Convert symbol to string if needed
    object_type_str = object_type.to_s

    # For some objects, we need to adjust the object_type name
    adjusted_type = case object_type_str
    when "leads"
                      "leads"
    else
                      object_type_str.end_with?("s") ? object_type_str : "#{object_type_str}s"
    end

    # Get all properties for this object type
    begin
      response = get_properties(object_type: adjusted_type)

      # Extract property definitions from the response
      property_definitions = {}
      if response.respond_to?(:results) && response.results.is_a?(Array)
        # Assuming response.results contains an array of property definition objects
        response.results.each do |prop|
          if prop.is_a?(Hash) && prop["name"]
            property_definitions[prop["name"]] = prop
          else
            Rails.logger.warn("Skipping an invalid property structure in response for #{object_type}: #{prop.inspect}")
          end
        end
      else
        # Fallback if response format is unexpected
        Rails.logger.warn("Unexpected response format from properties API for #{object_type}, expected results array.")
      end

      # Cache the result
      @property_cache[object_type.to_s] = property_definitions

      property_definitions
    rescue => e
      Rails.logger.error("Error fetching property definitions for #{object_type}: #{e.message}")
      # Return empty hash as fallback
      {}
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

  def get_contacts(limit: nil, after: nil, updated_after: nil)
    # Use search endpoint for both full and incremental syncs (max 200)
    limit = limit || 200
    limit = [ limit, 200 ].min

    with_rate_limiting(:search) do
      # Get all available contact property names
      all_property_names = get_all_property_definitions(:contacts).keys

      # Build the search request
      search_request = {
        limit: limit,
        after: after,
        properties: all_property_names.empty? ? nil : all_property_names,
        sorts: [ { propertyName: "lastmodifieddate", direction: "ASCENDING" } ]
      }

      # Add filter only if updated_after is provided
      if updated_after
        search_request[:filters] = [ {
          propertyName: "lastmodifieddate",
          operator: "GT",
          value: updated_after
        } ]
      end

      response = @client.crm.contacts.search_api.do_search(
        public_object_search_request: search_request
      )

      normalize_response(response)
    end
  end

  def get_companies(limit: nil, after: nil, updated_after: nil)
    # Use search endpoint for both full and incremental syncs (max 200)
    limit = limit || 200
    limit = [ limit, 200 ].min

    with_rate_limiting(:search) do
      # Get all available company property names
      all_property_names = get_all_property_definitions(:companies).keys

      # Build the search request
      search_request = {
        limit: limit,
        after: after,
        properties: all_property_names.empty? ? nil : all_property_names,
        sorts: [ { propertyName: "hs_lastmodifieddate", direction: "ASCENDING" } ]
      }

      # Add filter only if updated_after is provided
      if updated_after
        search_request[:filters] = [ {
          propertyName: "hs_lastmodifieddate",
          operator: "GT",
          value: updated_after
        } ]
      end

      response = @client.crm.companies.search_api.do_search(
        public_object_search_request: search_request
      )

      normalize_response(response)
    end
  end

  def get_deals(limit: nil, after: nil, updated_after: nil)
    # Use search endpoint for both full and incremental syncs (max 200)
    limit = limit || 200
    limit = [ limit, 200 ].min

    with_rate_limiting(:search) do
      # Get all available deal property names
      all_property_names = get_all_property_definitions(:deals).keys

      # Build the search request
      search_request = {
        limit: limit,
        after: after,
        properties: all_property_names.empty? ? nil : all_property_names,
        sorts: [ { propertyName: "hs_lastmodifieddate", direction: "ASCENDING" } ]
      }

      # Add filter only if updated_after is provided
      if updated_after
        search_request[:filters] = [ {
          propertyName: "hs_lastmodifieddate",
          operator: "GT",
          value: updated_after
        } ]
      end

      response = @client.crm.deals.search_api.do_search(
        public_object_search_request: search_request
      )

      normalize_response(response)
    end
  end

  def get_tickets(limit: nil, after: nil, updated_after: nil)
    # Use search endpoint for both full and incremental syncs (max 200)
    limit = limit || 200
    limit = [ limit, 200 ].min

    with_rate_limiting(:search) do
      # Get all available ticket property names
      all_property_names = get_all_property_definitions(:tickets).keys

      # Build the search request
      search_request = {
        limit: limit,
        after: after,
        properties: all_property_names.empty? ? nil : all_property_names,
        sorts: [ { propertyName: "hs_lastmodifieddate", direction: "ASCENDING" } ]
      }

      # Add filter only if updated_after is provided
      if updated_after
        search_request[:filters] = [ {
          propertyName: "hs_lastmodifieddate",
          operator: "GT",
          value: updated_after
        } ]
      end

      response = @client.crm.tickets.search_api.do_search(
        public_object_search_request: search_request
      )

      normalize_response(response)
    end
  end

  def get_leads(limit: nil, after: nil, updated_after: nil)
    # Use search endpoint for both full and incremental syncs (max 200)
    limit = limit || 200
    limit = [ limit, 200 ].min

    with_rate_limiting(:search) do
      # Get all available lead property names
      all_property_names = get_all_property_definitions(:leads).keys

      # Build the search request
      search_request = {
        limit: limit,
        after: after,
        filters: [],
        properties: all_property_names.empty? ? nil : all_property_names,
        sorts: [ { propertyName: "hs_lastmodifieddate", direction: "ASCENDING" } ]
      }

      # Add filter only if updated_after is provided
      if updated_after
        search_request[:filters] = [ {
          propertyName: "hs_lastmodifieddate",
          operator: "GT",
          value: updated_after
        } ]
      end

      response = @client.crm.objects.search_api.do_search(
        object_type: "leads",
        public_object_search_request: search_request
      )

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

  def get_call_records(limit: 40, after: nil, updated_after: nil)
    Rails.logger.warn("get_call_records method is deprecated - use get_calls instead")
    get_calls(limit: limit, after: after, updated_after: updated_after)
  end

  def get_calls(limit: 200, after: nil, updated_after: nil)
    # Use search endpoint for both full and incremental syncs (max 200)
    limit = limit || 200
    limit = [ limit, 200 ].min

    with_rate_limiting(:search) do
      # Get all available call property names
      all_property_names = get_all_property_definitions(:calls).keys

      # Build the search request
      search_request = {
        limit: limit,
        after: after,
        properties: all_property_names.empty? ? nil : all_property_names,
        sorts: [ { propertyName: "hs_lastmodifieddate", direction: "ASCENDING" } ]
      }

      # Add filter only if updated_after is provided
      if updated_after
        search_request[:filters] = [ {
          propertyName: "hs_lastmodifieddate",
          operator: "GT",
          value: updated_after
        } ]
      end

      response = @client.crm.objects.search_api.do_search(
        object_type: "calls",
        public_object_search_request: search_request
      )

      normalize_response(response)
    end
  end

  def get_emails(limit: 200, after: nil, updated_after: nil)
    # Use search endpoint for both full and incremental syncs (max 200)
    limit = limit || 200
    limit = [ limit, 200 ].min

    with_rate_limiting(:search) do
      # Get all available email property names
      all_property_names = get_all_property_definitions(:emails).keys

      # Build the search request
      search_request = {
        limit: limit,
        after: after,
        properties: all_property_names.empty? ? nil : all_property_names,
        sorts: [ { propertyName: "hs_lastmodifieddate", direction: "ASCENDING" } ]
      }

      # Add filter only if updated_after is provided
      if updated_after
        search_request[:filters] = [ {
          propertyName: "hs_lastmodifieddate",
          operator: "GT",
          value: updated_after
        } ]
      end

      response = @client.crm.objects.search_api.do_search(
        object_type: "emails",
        public_object_search_request: search_request
      )

      normalize_response(response)
    end
  end

  def get_meetings(limit: 200, after: nil, updated_after: nil)
    # Use search endpoint for both full and incremental syncs (max 200)
    limit = limit || 200
    limit = [ limit, 200 ].min

    with_rate_limiting(:search) do
      # Get all available meeting property names
      all_property_names = get_all_property_definitions(:meetings).keys

      # Build the search request
      search_request = {
        limit: limit,
        after: after,
        properties: all_property_names.empty? ? nil : all_property_names,
        sorts: [ { propertyName: "hs_lastmodifieddate", direction: "ASCENDING" } ]
      }

      # Add filter only if updated_after is provided
      if updated_after
        search_request[:filters] = [ {
          propertyName: "hs_lastmodifieddate",
          operator: "GT",
          value: updated_after
        } ]
      end

      response = @client.crm.objects.search_api.do_search(
        object_type: "meetings",
        public_object_search_request: search_request
      )

      normalize_response(response)
    end
  end

  def get_notes(limit: 200, after: nil, updated_after: nil)
    # Use search endpoint for both full and incremental syncs (max 200)
    limit = limit || 200
    limit = [ limit, 200 ].min

    with_rate_limiting(:search) do
      # Get all available note property names
      all_property_names = get_all_property_definitions(:notes).keys

      # Build the search request
      search_request = {
        limit: limit,
        after: after,
        properties: all_property_names.empty? ? nil : all_property_names,
        sorts: [ { propertyName: "hs_lastmodifieddate", direction: "ASCENDING" } ]
      }

      # Add filter only if updated_after is provided
      if updated_after
        search_request[:filters] = [ {
          propertyName: "hs_lastmodifieddate",
          operator: "GT",
          value: updated_after
        } ]
      end

      response = @client.crm.objects.search_api.do_search(
        object_type: "notes",
        public_object_search_request: search_request
      )

      normalize_response(response)
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
