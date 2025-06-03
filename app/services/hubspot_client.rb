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

  # Search for contacts by email addresses
  # @param emails [Array<String>] Array of email addresses to search for
  # @return [Hash] Hash with email as key and contact data as value
  def contacts_by_email(emails)
    return {} if emails.empty?

    all_results = {}

    # HubSpot allows maximum 6 filters per filter group, so we need to chunk emails
    emails.each_slice(6) do |email_chunk|
      with_rate_limiting(:search) do
        all_property_names = get_all_property_definitions(:contacts).keys

        # Build filters for each email in this chunk
        filters = email_chunk.map do |email|
          {
            propertyName: "email",
            operator: "EQ",
            value: email
          }
        end

        search_request = {
          limit: 100,
          properties: all_property_names.empty? ? [ "email", "hs_object_id" ] : all_property_names,
          filterGroups: [
            {
              filters: filters
            }
          ]
        }

        response = @client.crm.contacts.search_api.do_search(
          public_object_search_request: search_request
        )

        # Convert response to a hash with email as keys for easier lookup
        if response&.results
          response.results.each do |contact|
            contact_hash = contact.respond_to?(:to_hash) ? contact.to_hash : contact
            if contact_hash.is_a?(Hash) && contact_hash["properties"] && contact_hash["properties"]["email"]
              email = contact_hash["properties"]["email"]
              all_results[email] = contact_hash
            end
          end
        end
      end
    end

    all_results
  end

  # Create a new contact in HubSpot
  # @param email [String] Email address for the contact
  # @param additional_properties [Hash] Additional properties to set on the contact
  # @return [Hash] Created contact data
  def create_contact(email, sa_id, sa_source, additional_properties = {})
    with_rate_limiting(:default) do
      properties = {
        "email" => email,
        "sa_id" => sa_id,
        "sa_source" => sa_source
      }.merge(additional_properties)

      contact_input = {
        properties: properties
      }

      response = @client.crm.contacts.basic_api.create(
        simple_public_object_input: contact_input
      )

      response.respond_to?(:to_hash) ? response.to_hash : response
    end
  end

  # Helper method to handle HubSpot's 10k search result limit by restarting searches
  # when approaching the limit using the last modified date
  #
  # HubSpot's search API has a hard limit of 10,000 results per search, even with pagination.
  # This method works around this limitation by:
  #
  # 1. Performing normal pagination until we approach 9,000 results (safety buffer)
  # 2. Extracting the lastmodifieddate from the final record
  # 3. Starting a new search using that date as the updated_after filter
  # 4. Repeating this process until no more results are found
  #
  # This allows us to fetch unlimited results while respecting HubSpot's API constraints.
  # The method is transparent to callers - they receive all results as if it was one search.
  #
  # @param object_type [Symbol] The type of HubSpot object (:contacts, :deals, etc.)
  # @param limit [Integer] Results per page (max 200)
  # @param after [String] Pagination cursor for the first search
  # @param updated_after [String] ISO8601 timestamp to filter results modified after this date
  # @return [OpenStruct] Response with all results and no paging info
  def search_with_10k_limit_handling(object_type, limit: nil, after: nil, updated_after: nil)
    limit = limit || 200
    limit = [ limit, 200 ].min

    all_results = []
    current_after = after
    current_updated_after = updated_after
    total_results_in_current_search = 0
    search_restart_threshold = 9000 # Restart before hitting 10k limit
    restart_count = 0
    batch_count = 0 # Track total batches for development mode limit

    Rails.logger.info("Starting search for #{object_type} with 10k limit handling. Initial updated_after: #{current_updated_after}")

    loop do
      # Development mode safety limit - only process 3 batches total
      if Rails.env.development? && batch_count >= 300
        Rails.logger.info("#{object_type}: Development mode - stopping after 3 batches")
        break
      end

      batch_count += 1

      # Make the search call for this object type
      response = case object_type
      when :contacts
        make_contacts_search(limit, current_after, current_updated_after)
      when :companies
        make_companies_search(limit, current_after, current_updated_after)
      when :deals
        make_deals_search(limit, current_after, current_updated_after)
      when :tickets
        make_tickets_search(limit, current_after, current_updated_after)
      when :leads
        make_leads_search(limit, current_after, current_updated_after)
      when :calls
        make_calls_search(limit, current_after, current_updated_after)
      when :emails
        make_emails_search(limit, current_after, current_updated_after)
      when :meetings
        make_meetings_search(limit, current_after, current_updated_after)
      when :notes
        make_notes_search(limit, current_after, current_updated_after)
      else
        raise "Unsupported object type for search with 10k handling: #{object_type}"
      end

      results = response&.results || []
      break if results.empty?

      all_results.concat(results)
      total_results_in_current_search += results.size

      Rails.logger.debug("#{object_type}: Batch returned #{results.size} results. Total in current search: #{total_results_in_current_search}, Overall total: #{all_results.size}")

      # Check if we need to restart the search due to approaching 10k limit
      if total_results_in_current_search >= search_restart_threshold
        restart_count += 1
        Rails.logger.info("#{object_type}: Approaching 10k limit (#{total_results_in_current_search} results), restarting search ##{restart_count}")

        # Extract the last modified date from the last result
        last_result = results.last
        last_modified_date = last_result&.updated_at
        if last_modified_date
          # Restart the search with the new updated_after filter
          current_updated_after = last_modified_date
          current_after = nil # Reset pagination
          total_results_in_current_search = 0
          Rails.logger.info("#{object_type}: Restarting search ##{restart_count} from date: #{last_modified_date}")
          next
        else
          Rails.logger.warn("#{object_type}: Could not extract last modified date, continuing with normal pagination")
        end
      end

      # Continue with normal pagination
      current_after = response.paging&.next&.after
      break unless current_after
    end

    Rails.logger.info("#{object_type}: Completed search with #{restart_count} restarts. Total results: #{all_results.size}")

    # Return response in the expected format
    OpenStruct.new(
      results: all_results,
      paging: nil # No paging since we've collected all results
    )
  end



  # Individual search methods for each object type (extracted from main methods)
  def make_contacts_search(limit, after, updated_after)
    with_rate_limiting(:search) do
      all_property_names = get_all_property_definitions(:contacts).keys

      search_request = {
        limit: limit,
        after: after,
        properties: all_property_names.empty? ? nil : all_property_names,
        sorts: [ { propertyName: "lastmodifieddate", direction: "ASCENDING" } ]
      }

      if updated_after
        search_request[:filters] = [ {
          propertyName: "lastmodifieddate",
          operator: "GT",
          value: updated_after
        } ]
      end

      puts "Search #{limit} #{after} #{updated_after}"
      response = @client.crm.contacts.search_api.do_search(
        public_object_search_request: search_request
      )

      normalize_response(response)
    end
  end

  def make_companies_search(limit, after, updated_after)
    with_rate_limiting(:search) do
      all_property_names = get_all_property_definitions(:companies).keys

      search_request = {
        limit: limit,
        after: after,
        properties: all_property_names.empty? ? nil : all_property_names,
        sorts: [ { propertyName: "hs_lastmodifieddate", direction: "ASCENDING" } ]
      }

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

  def make_deals_search(limit, after, updated_after)
    with_rate_limiting(:search) do
      all_property_names = get_all_property_definitions(:deals).keys

      search_request = {
        limit: limit,
        after: after,
        properties: all_property_names.empty? ? nil : all_property_names,
        sorts: [ { propertyName: "hs_lastmodifieddate", direction: "ASCENDING" } ]
      }

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

  def make_tickets_search(limit, after, updated_after)
    with_rate_limiting(:search) do
      all_property_names = get_all_property_definitions(:tickets).keys

      search_request = {
        limit: limit,
        after: after,
        properties: all_property_names.empty? ? nil : all_property_names,
        sorts: [ { propertyName: "hs_lastmodifieddate", direction: "ASCENDING" } ]
      }

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

  def make_leads_search(limit, after, updated_after)
    with_rate_limiting(:search) do
      all_property_names = get_all_property_definitions(:leads).keys

      search_request = {
        limit: limit,
        after: after,
        filters: [],
        properties: all_property_names.empty? ? nil : all_property_names,
        sorts: [ { propertyName: "hs_lastmodifieddate", direction: "ASCENDING" } ]
      }

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

  def make_calls_search(limit, after, updated_after)
    with_rate_limiting(:search) do
      all_property_names = get_all_property_definitions(:calls).keys

      search_request = {
        limit: limit,
        after: after,
        properties: all_property_names.empty? ? nil : all_property_names,
        sorts: [ { propertyName: "hs_lastmodifieddate", direction: "ASCENDING" } ]
      }

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

  def make_emails_search(limit, after, updated_after)
    with_rate_limiting(:search) do
      all_property_names = get_all_property_definitions(:emails).keys

      search_request = {
        limit: limit,
        after: after,
        properties: all_property_names.empty? ? nil : all_property_names,
        sorts: [ { propertyName: "hs_lastmodifieddate", direction: "ASCENDING" } ]
      }

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

  def make_meetings_search(limit, after, updated_after)
    with_rate_limiting(:search) do
      all_property_names = get_all_property_definitions(:meetings).keys

      search_request = {
        limit: limit,
        after: after,
        properties: all_property_names.empty? ? nil : all_property_names,
        sorts: [ { propertyName: "hs_lastmodifieddate", direction: "ASCENDING" } ]
      }

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

  def make_notes_search(limit, after, updated_after)
    with_rate_limiting(:search) do
      all_property_names = get_all_property_definitions(:notes).keys

      search_request = {
        limit: limit,
        after: after,
        properties: all_property_names.empty? ? nil : all_property_names,
        sorts: [ { propertyName: "hs_lastmodifieddate", direction: "ASCENDING" } ]
      }

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

  def get_contacts(limit: nil, after: nil, updated_after: nil)
    search_with_10k_limit_handling(:contacts, limit: limit, after: after, updated_after: updated_after)
  end

  def get_companies(limit: nil, after: nil, updated_after: nil)
    search_with_10k_limit_handling(:companies, limit: limit, after: after, updated_after: updated_after)
  end

  def get_deals(limit: nil, after: nil, updated_after: nil)
    search_with_10k_limit_handling(:deals, limit: limit, after: after, updated_after: updated_after)
  end

  def get_tickets(limit: nil, after: nil, updated_after: nil)
    search_with_10k_limit_handling(:tickets, limit: limit, after: after, updated_after: updated_after)
  end

  def get_leads(limit: nil, after: nil, updated_after: nil)
    search_with_10k_limit_handling(:leads, limit: limit, after: after, updated_after: updated_after)
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
    search_with_10k_limit_handling(:calls, limit: limit, after: after, updated_after: updated_after)
  end

  def get_emails(limit: 200, after: nil, updated_after: nil)
    search_with_10k_limit_handling(:emails, limit: limit, after: after, updated_after: updated_after)
  end

  def get_meetings(limit: 200, after: nil, updated_after: nil)
    search_with_10k_limit_handling(:meetings, limit: limit, after: after, updated_after: updated_after)
  end

  def get_notes(limit: 200, after: nil, updated_after: nil)
    search_with_10k_limit_handling(:notes, limit: limit, after: after, updated_after: updated_after)
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

    max_retries = 3
    retry_count = 0
    base_delay = 2 # seconds

    begin
      response = yield
      manager.record_request
      response
    rescue => e
      manager.record_request

      if e.message.include?("too many requests") || (e.respond_to?(:response) && e.response&.code == 429)
        Rails.logger.warn("Hubspot rate limit hit for #{endpoint_type}, retrying after delay")
        sleep(10)
        retry
      elsif (response && response&.code.to_s.start_with?("4")) && retry_count < max_retries
        retry_count += 1
        delay = base_delay ** retry_count
        Rails.logger.warn("Hubspot API returned 4xx error for #{endpoint_type}, retry #{retry_count}/#{max_retries} after #{delay} seconds: #{e.message}")
        sleep(delay)
        retry
      else
        raise e
      end
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
