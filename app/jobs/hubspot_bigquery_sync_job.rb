# app/jobs/hubspot_bigquery_sync_job.rb

require "google/cloud/bigquery"
require "json"
require "tempfile"

class HubspotBigquerySyncJob < ApplicationJob
  queue_as :default

  # Helper method for running in Rails console (especially in development)
  def self.run_now(object_type = nil, full_sync: false)
    puts "Starting HubspotBigquerySyncJob manually from console for #{object_type || 'all objects'}. Full sync: #{full_sync}"
    Rails.logger.info("Starting HubspotBigquerySyncJob manually from console for #{object_type || 'all objects'}. Full sync: #{full_sync}")
    job = self.new
    job.perform(object_type, full_sync: full_sync)
  rescue => e
    # When run from the console, we want to see the full error
    puts "Error in HubspotBigquerySyncJob: #{e.class} - #{e.message}"
    puts e.backtrace
    Rails.logger.error("Error in HubspotBigquerySyncJob: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise e
  end

  HUBSPOT_OBJECTS = {
    contacts: { id_field: "id", batch_size: 100, supports_incremental: true },
    companies: { id_field: "id", batch_size: 100, supports_incremental: true },
    deals: { id_field: "id", batch_size: 100, supports_incremental: true },
    tickets: { id_field: "id", batch_size: 100, supports_incremental: true },
    owners: { id_field: "id", batch_size: 100, supports_incremental: false },
    engagements: { id_field: "id", batch_size: 100, legacy: true, supports_incremental: true },
    deal_pipelines: { id_field: "id", batch_size: 100, single_batch: true, supports_incremental: false },
    deal_stages: { id_field: "id", batch_size: 100, single_batch: true, supports_incremental: false },
    workflows: { id_field: "id", batch_size: 50, legacy: true, supports_incremental: false },
    properties: { id_field: "name", batch_size: 100, single_batch: true, property_groups: [ "contacts", "companies", "deals", "tickets" ], supports_incremental: false },
    lists: { id_field: "listId", batch_size: 30, legacy: true, supports_incremental: false },
    call_records: { id_field: "id", batch_size: 40, legacy: true, supports_incremental: true },
    meetings: { id_field: "id", batch_size: 50, supports_incremental: true }
  }

  def perform(object_type = nil, full_sync: false)
    Rails.logger.info("Starting HubspotBigquerySyncJob for #{object_type || 'all objects'}. Full sync: #{full_sync}")
    puts "Starting HubspotBigquerySyncJob for #{object_type || 'all objects'}. Full sync: #{full_sync}"

    # Add more detailed environment info in development for debugging
    if Rails.env.development?
      Rails.logger.debug("Environment:")
      Rails.logger.debug("- HUBSPOT_ACCESS_TOKEN present: #{ENV["HUBSPOT_ACCESS_TOKEN"].present?}")
      Rails.logger.debug("- GOOGLE_CLOUD_PROJECT: #{ENV["GOOGLE_CLOUD_PROJECT"]}")
      Rails.logger.debug("- BIGQUERY_DATASET: #{ENV["BIGQUERY_DATASET"]}")

      puts "Environment:"
      puts "- HUBSPOT_ACCESS_TOKEN present: #{ENV["HUBSPOT_ACCESS_TOKEN"].present?}"
      puts "- GOOGLE_CLOUD_PROJECT: #{ENV["GOOGLE_CLOUD_PROJECT"]}"
      puts "- BIGQUERY_DATASET: #{ENV["BIGQUERY_DATASET"]}"
    end

    unless ENV["HUBSPOT_ACCESS_TOKEN"].present?
      error_message = "HUBSPOT_ACCESS_TOKEN is not configured"
      log_error("Hubspot BigQuery Sync Failed", error_message)
      raise error_message
    end

    begin
      if object_type.present?
        if HUBSPOT_OBJECTS.key?(object_type.to_sym)
          sync_object(object_type.to_sym, full_sync: full_sync)
        else
          log_error("Hubspot BigQuery Sync Warning", "Unknown object type: #{object_type}")
          Rails.logger.warn("Unknown object type: #{object_type}. Available types: #{HUBSPOT_OBJECTS.keys.join(', ')}")
        end
      else
        # Sync all objects
        HUBSPOT_OBJECTS.keys.each do |object|
          begin
            sync_object(object, full_sync: full_sync)
          rescue => e
            error_message = "Error syncing object type #{object}: #{e.message}"
            log_error("Hubspot BigQuery Sync Error - #{object}", error_message)
            # Continue with next object instead of failing the entire job
            next if Rails.env.production?
            # In development, we'll raise the error for easier debugging
            raise e unless Rails.env.production?
          end
        end
      end

      # Record the success
      HubspotSyncStatus.create_or_update(
        object_type: object_type || "all",
        status: "success",
        synced_at: Time.current,
        record_count: @records_processed
      )
    rescue => e
      error_message = "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
      log_error("Hubspot BigQuery Sync Error - #{object_type || 'all'}", error_message)

      # Record the failure
      HubspotSyncStatus.create_or_update(
        object_type: object_type || "all",
        status: "error",
        error_message: "#{e.class}: #{e.message}"
      )

      raise e
    end
  end

  private

  def log_error(title, message)
    if Rails.env.development?
      # Just log to console in development
      Rails.logger.error("#{title}: #{message}")
      # Dump more info to help with debugging
      if message.include?("Hubspot API Error")
        Rails.logger.debug("API Error Details:")
        Rails.logger.debug("- Hubspot Access Token first 10 chars: #{ENV['HUBSPOT_ACCESS_TOKEN'].to_s[0..9]}")
        Rails.logger.debug("- Token length: #{ENV['HUBSPOT_ACCESS_TOKEN'].to_s.length}")
      end
    else
      # Create ErrorLog record in production (which will trigger email)
      ErrorLog.create(title: title, body: message)
    end
  end

  def sync_object(object_type, full_sync: false)
    @records_processed = 0
    Rails.logger.info("Syncing Hubspot #{object_type}. Full sync: #{full_sync}")
    puts "Syncing Hubspot #{object_type}. Full sync: #{full_sync}"

    # Setup BigQuery
    bigquery = initialize_bigquery_client
    dataset = initialize_bigquery_dataset(bigquery)
    table_name = "hubspot_#{object_type}"
    table = dataset.table(table_name) || create_table(dataset, table_name)

    # First update the schema to ensure all properties are included
    update_schema_for_object(object_type, table, dataset, bigquery)

    # Get data and sync
    object_config = HUBSPOT_OBJECTS[object_type]

    if object_config[:single_batch]
      # For objects that are retrieved in a single API call
      records = get_object_records_single_batch(object_type)
      sync_records_to_bigquery(records, table, dataset, bigquery, object_type)
    else
      # For paginated objects
      # Get the last sync time if we're doing an incremental sync
      last_sync_time = nil
      if !full_sync && object_config[:supports_incremental]
        last_sync_time = get_last_sync_time(object_type)
        Rails.logger.info("Incremental sync for #{object_type} since #{last_sync_time || 'never'}")
        puts "Incremental sync for #{object_type} since #{last_sync_time || 'never'}"
      end

      sync_paginated_records(object_type, object_config, table, dataset, bigquery, last_sync_time)
    end

    Rails.logger.info("Completed syncing #{object_type} - processed #{@records_processed} records")
    puts "Completed syncing #{object_type} - processed #{@records_processed} records"
  end

  def get_last_sync_time(object_type)
    # Get the last successful sync time for this object type
    last_sync = HubspotSyncStatus.last_successful_sync(object_type.to_s)

    if last_sync&.synced_at
      # Return the time in ISO8601 format
      last_sync.synced_at.iso8601
    else
      # If no previous successful sync, return nil (which will trigger a full sync)
      nil
    end
  end

  def sync_paginated_records(object_type, object_config, table, dataset, bigquery, last_sync_time = nil)
    after = nil
    has_more = true
    batch_counter = 0
    batch_limit = object_config[:batch_size]

    # For legacy APIs that use offset instead of cursor pagination
    offset = 0

    while has_more
      begin
        batch_counter += 1
        Rails.logger.info("Fetching #{object_type} batch ##{batch_counter} (limit: #{batch_limit}, after: #{after || offset})")

        if object_config[:legacy]
          # Legacy APIs don't natively support incremental sync
          response = hubspot_client.send("get_#{object_type}", limit: batch_limit, offset: offset)
          records = process_legacy_response(response, object_type)
          offset = response["offset"] || response.offset if response.respond_to?(:offset) || response.respond_to?(:[])
          has_more = response["hasMore"] || response.hasMore || false if response.respond_to?(:hasMore) || response.respond_to?(:[])

          # If doing incremental sync, filter records by updated_at
          if last_sync_time.present?
            # Filter records that were updated after last sync time
            records = filter_updated_records(records, last_sync_time, object_type)
          end
        else
          # Modern APIs support fetching recently updated records
          if last_sync_time.present? && object_config[:supports_incremental]
            # For incremental sync, use the updated_after parameter
            response = hubspot_client.send("get_#{object_type}", limit: batch_limit, after: after, updated_after: last_sync_time)
          else
            # For full sync
            response = hubspot_client.send("get_#{object_type}", limit: batch_limit, after: after)
          end

          # Check if response is structured as expected
          if response.respond_to?(:results)
            records = response.results
          elsif response.is_a?(Hash) && response["results"]
            records = response["results"]
          else
            Rails.logger.error("Unexpected response format for #{object_type}: #{response.class}")
            records = []
          end

          # Get the next cursor for pagination (responses are now normalized)
          after = response.paging&.next&.after if response.respond_to?(:paging)
          has_more = after.present?
        end

        if records.present?
          @records_processed += records.size
          sync_records_to_bigquery(records, table, dataset, bigquery, object_type)
        else
          has_more = false
        end

        # Safety limit for development
        if Rails.env.development? && batch_counter >= 3
          Rails.logger.info("Development mode - stopping after 3 batches")
          has_more = false
        end

        # Add a small delay between batches to avoid overloading the API
        sleep(1) if has_more
      rescue => e
        error_message = "Error in batch ##{batch_counter} for #{object_type}: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
        log_error("Hubspot BigQuery Sync Error - #{object_type} Batch ##{batch_counter}", error_message)
        # Continue with next batch instead of failing the entire job
        next
      end
    end
  end

  def filter_updated_records(records, last_sync_time, object_type)
    parsed_sync_time = Time.parse(last_sync_time)

    # Filter records based on their update timestamp
    filtered_records = records.select do |record|
      # Different objects have different update time field names
      update_time = case object_type
      when :engagements
                      Time.at(record[:updated_at].to_i / 1000) if record[:updated_at]
      else
                      # Try standard fields
                      if record["updatedAt"]
                        Time.at(record["updatedAt"].to_i / 1000)
                      elsif record["updated_at"]
                        Time.parse(record["updated_at"].to_s)
                      elsif record["lastUpdated"]
                        Time.at(record["lastUpdated"].to_i / 1000)
                      else
                        # Default to current time to include record if no update time found
                        Time.current
                      end
      end

      # Include records that were updated after the last sync time
      update_time && update_time > parsed_sync_time
    end

    Rails.logger.info("Filtered from #{records.size} to #{filtered_records.size} records for incremental sync")
    filtered_records
  end

  def get_object_records_single_batch(object_type)
    case object_type
    when :deal_pipelines
      response = hubspot_client.get_deal_pipelines
      # Handle the specific structure of pipelines response
      response.results.map do |pipeline|
        pipeline_data = pipeline.to_hash
        # Add stages as a nested field
        pipeline_data[:stages] = pipeline.stages.map(&:to_hash) if pipeline.stages
        pipeline_data
      end
    when :deal_stages
      response = hubspot_client.get_deal_stages
      response.results
    when :properties
      # Properties are special because we need to get properties for each object type
      all_properties = []

      # For each object type (contacts, companies, deals, etc.)
      HUBSPOT_OBJECTS[object_type][:property_groups].each do |group|
        response = hubspot_client.get_properties(object_type: group)
        # Add the object type to each property
        properties = response.results.map do |prop|
          prop["object_type"] = group
          prop
        end
        all_properties.concat(properties)
      end

      all_properties
    else
      []
    end
  end

  def process_legacy_response(response, object_type)
    case object_type
    when :engagements
      response["results"].map do |engagement|
        # Transform the engagement object to match our expected format
        {
          id: engagement["engagement"]["id"],
          type: engagement["engagement"]["type"],
          timestamp: engagement["engagement"]["timestamp"],
          created_at: Time.at(engagement["engagement"]["createdAt"] / 1000).utc.to_datetime,
          updated_at: Time.at(engagement["engagement"]["lastUpdated"] / 1000).utc.to_datetime,
          owner_id: engagement["engagement"]["ownerId"],
          portal_id: engagement["engagement"]["portalId"],
          active: engagement["engagement"]["active"],
          associations: engagement["associations"],
          metadata: engagement["metadata"]
        }
      end
    when :workflows
      response.results.map do |workflow|
        workflow_data = workflow.is_a?(Hash) ? workflow : workflow.to_hash
        workflow_data
      end
    when :lists
      response.results.map do |list|
        list_data = list.is_a?(Hash) ? list : list.to_hash
        list_data
      end
    when :call_records
      response.results.map do |call|
        call_data = call.is_a?(Hash) ? call : call.to_hash
        call_data
      end
    else
      response["results"] || []
    end
  end

  def sync_records_to_bigquery(records, table, dataset, bigquery, object_type)
    return if records.empty?

    # Debug info in development
    if Rails.env.development?
      debug("Processing #{records.size} records for #{object_type}")

      # Show structure of the first record
      if records.first.is_a?(Hash)
        sample_record = records.first
        debug("Sample record keys: #{sample_record.keys.join(', ')}")

        if sample_record["properties"].is_a?(Hash)
          property_count = sample_record["properties"].keys.size
          sample_props = sample_record["properties"].keys.first(10)
          debug("Properties count: #{property_count}, First 10 properties: #{sample_props.join(', ')}")

          # Use our detailed debug function on the first record
          debug_record_properties(sample_record, object_type)
        end
      end
    end

    # Process records into a format suitable for BigQuery
    processed_records = []
    schema = {}

    records.each do |record|
      # Convert to hash if it's an object
      record_hash = record.is_a?(Hash) ? record : record.to_hash

      # Add timestamp fields if missing
      record_hash[:synced_at] = Time.current.utc.iso8601

      # For CRM objects, extract all properties from the properties hash
      expanded_record = expand_properties(record_hash, object_type)

      # In development, debug the expanded record as well
      if Rails.env.development? && records.index(record) == 0
        debug("First expanded record keys: #{expanded_record.keys.join(', ')}")
        debug("Sample property values in expanded record:")
        if record_hash["properties"].is_a?(Hash)
          sample_props = record_hash["properties"].keys.first(5)
          sample_props.each do |prop|
            debug("  - #{prop}: #{expanded_record[prop]}")
          end
        end
      end

      # Flatten the record and update schema
      data, record_schema = flatten_attributes(expanded_record)
      processed_records << data
      schema.merge!(record_schema) { |_key, old_val, new_val| merge_schemas(old_val, new_val) }
    end

    # Ensure tables have the right schema
    update_table_schema(table, schema)

    # Use a temp file to upload the data
    Tempfile.open([ "hubspot_#{object_type}", ".json" ]) do |tempfile|
      processed_records.each do |data_row|
        tempfile.puts data_row.to_json
      end
      tempfile.flush

      # Load the data into BigQuery
      load_job = table.load_job tempfile, format: :json
      load_job.wait_until_done!

      if load_job.failed?
        error_message = "Failed to load #{object_type} data to BigQuery: #{load_job.error.inspect}"
        log_error("Hubspot BigQuery Sync Error - #{object_type}", error_message)
      end
    end
  end

  # Helper method for development debugging
  def debug(message)
    if Rails.env.development?
      Rails.logger.debug("[HubspotDebug] #{message}")
    end
  end

  # Extract all properties from nested properties hash
  def expand_properties(record, object_type)
    expanded = record.dup

    # Handle Hubspot API objects (like SimplePublicObjectWithAssociations)
    if !expanded.is_a?(Hash) && expanded.respond_to?(:to_hash)
      expanded = expanded.to_hash
    end

    # Handle Hubspot objects that have properties as an attribute rather than a hash key
    if !expanded.is_a?(Hash) && expanded.respond_to?(:properties)
      properties = expanded.properties

      # Try to convert properties to a hash if it's an object
      if properties.respond_to?(:to_hash)
        properties = properties.to_hash
      end

      if properties.is_a?(Hash)
        expanded = { "properties" => properties }

        # Add other attributes that might be available
        expanded["id"] = expanded.id if expanded.respond_to?(:id)
        expanded["createdAt"] = expanded.created_at if expanded.respond_to?(:created_at)
        expanded["updatedAt"] = expanded.updated_at if expanded.respond_to?(:updated_at)
        expanded["archived"] = expanded.archived if expanded.respond_to?(:archived)
      end
    end

    # If this is a CRM object with properties hash, expand it
    if expanded.is_a?(Hash) && expanded.key?("properties")
      properties = expanded["properties"]

      if properties.is_a?(Hash)
        # For each property, add it directly to the record
        properties.each do |prop_name, prop_value|
          # Ensure we don't overwrite existing fields
          unless expanded.key?(prop_name)
            expanded[prop_name] = prop_value
          end
        end

        # Keep the original properties hash in a field called all_properties
        expanded["all_properties"] = properties
      end
    end

    # Handle special case for engagements and other legacy objects
    if object_type == :engagements && expanded.is_a?(Hash) && expanded.key?("metadata")
      # Extract metadata fields into top-level properties
      if expanded["metadata"].is_a?(Hash)
        expanded["metadata"].each do |meta_key, meta_value|
          expanded["metadata_#{meta_key}"] = meta_value
        end
      end
    end

    expanded
  end

  def initialize_bigquery_client
    if Rails.env.development?
      begin
        # In development, try parsing the credentials directly first
        credentials = JSON.parse(ENV["GOOGLE_CLOUD_CREDENTIALS"])

        Google::Cloud::Bigquery.new(
          project: ENV["GOOGLE_CLOUD_PROJECT"],
          credentials: credentials
        )
      rescue JSON::ParserError => e
        # Log the error for debugging
        Rails.logger.warn("Error parsing GOOGLE_CLOUD_CREDENTIALS: #{e.message}. Trying alternative format.")

        # If direct parsing fails, try with the format manipulation
        Google::Cloud::Bigquery.new(
          project: ENV["GOOGLE_CLOUD_PROJECT"],
          credentials: JSON.parse(ENV["GOOGLE_CLOUD_CREDENTIALS"].gsub(/(?<!\\)(\\n)/, "").gsub('\n', "n"))
        )
      end
    else
      # Production implementation - use the format manipulation that's known to work
      Google::Cloud::Bigquery.new(
        project: ENV["GOOGLE_CLOUD_PROJECT"],
        credentials: JSON.parse(ENV["GOOGLE_CLOUD_CREDENTIALS"].gsub(/(?<!\\)(\\n)/, "").gsub('\n', "n"))
      )
    end
  rescue => e
    error_message = "Failed to initialize BigQuery client: #{e.message}"
    log_error("BigQuery Client Initialization Error", error_message)
    raise e
  end

  def initialize_bigquery_dataset(bigquery)
    dataset_id = ENV["BIGQUERY_DATASET"]
    dataset = bigquery.dataset(dataset_id)

    unless dataset
      Rails.logger.info("Creating BigQuery dataset: #{dataset_id}")
      dataset = bigquery.create_dataset(dataset_id)
    end

    dataset
  end

  def create_table(dataset, table_name)
    Rails.logger.info("Creating BigQuery table: #{table_name}")

    dataset.create_table(table_name) do |schema|
      schema.string "id", mode: "REQUIRED"
      schema.timestamp "synced_at"
      # Basic schema - will be expanded dynamically
    end
  end

  # Updated flatten_attributes method to handle nested properties better
  def flatten_attributes(attributes, parent_field = nil)
    data = {}
    schema = {}

    # First, handle the special case of Hubspot properties
    if attributes.is_a?(Hash) && attributes["properties"].is_a?(Hash) && parent_field.nil?
      # Directly include all properties at the top level
      attributes["properties"].each do |prop_name, prop_value|
        clean_name = sanitize_field_name(prop_name)
        data[clean_name] = prop_value
        schema[clean_name] = { type: infer_bigquery_type(prop_value, clean_name), mode: "NULLABLE" }
      end
    end

    # Then process all other attributes normally
    attributes.each do |key, value|
      # Skip "properties" since we already processed it
      next if key == "properties" && value.is_a?(Hash) && parent_field.nil?

      current_field = parent_field ? "#{parent_field}.#{key}" : key.to_s

      # Clean up field name
      field_name = sanitize_field_name(current_field)
      next if field_name.nil?

      # Skip properties_ prefix on fields that come from properties hash
      if field_name.start_with?("properties_")
        field_name = field_name.sub(/^properties_/, "")
      end

      if value.is_a?(Hash)
        nested_data, nested_schema = flatten_attributes(value, key.to_s)
        data.merge!(nested_data)
        schema.merge!(nested_schema) { |_k, old_val, new_val| merge_schemas(old_val, new_val) }
      elsif value.is_a?(Array)
        # Handle array values by converting to JSON strings
        if value.any?
          # Convert the array to a properly formatted JSON string
          # This ensures BigQuery can properly store arrays without errors
          data[field_name] = JSON.generate(value)
          schema[field_name] = { type: "STRING", mode: "NULLABLE" }
        else
          # Empty array
          data[field_name] = "[]"
          schema[field_name] = { type: "STRING", mode: "NULLABLE" }
        end
      else
        # Handle primitive values
        data[field_name] = value
        schema[field_name] = { type: infer_bigquery_type(value, field_name), mode: "NULLABLE" }
      end
    end

    [ data, schema ]
  end

  def sanitize_field_name(field_name)
    # Replace any invalid characters with underscores
    sanitized = field_name.to_s.gsub(/[^a-zA-Z0-9_]/, "_")

    # Ensure the field name starts with a letter or underscore
    sanitized = "_#{sanitized}" unless sanitized.match?(/^[a-zA-Z_]/)

    # Truncate if too long for BigQuery
    if sanitized.length > 128
      sanitized = sanitized[0..127]
    end

    sanitized
  end

  def infer_bigquery_type(value, field_name = nil)
    return "TIMESTAMP" if field_name&.end_with?("_ts")

    case value
    when Integer
      "INTEGER"
    when Float
      "FLOAT"
    when TrueClass, FalseClass
      "BOOLEAN"
    when Time, DateTime, ActiveSupport::TimeWithZone
      "TIMESTAMP"
    when Array
      if value.empty?
        "STRING"
      else
        infer_bigquery_type(value.first)
      end
    else
      "STRING"
    end
  end

  def update_table_schema(table, data_schema)
    existing_fields = collect_existing_fields(table.schema.fields).map(&:downcase)
    new_fields = data_schema.keys.select { |key| !existing_fields.include?(key.downcase) }

    return if new_fields.empty?

    table.schema do |schema|
      new_fields.each do |field_name|
        field_info = data_schema[field_name]
        add_field_to_schema(schema, field_name, field_info)
      end
    end
  end

  def collect_existing_fields(fields, prefix = nil)
    field_names = []
    fields.each do |field|
      full_name = prefix ? "#{prefix}.#{field.name}" : field.name
      field_names << full_name
      if field.type == "RECORD" && field.fields.any?
        field_names.concat(collect_existing_fields(field.fields, full_name))
      end
    end
    field_names
  end

  def add_field_to_schema(schema, field_name, field_info)
    schema.send(
      field_info[:type].downcase,
      field_name,
      mode: field_info[:mode]
    )
  end

  def merge_schemas(old_val, new_val)
    if old_val.is_a?(Hash) && new_val.is_a?(Hash)
      old_val.merge(new_val) { |_key, old_subval, new_subval| merge_schemas(old_subval, new_subval) }
    else
      new_val
    end
  end

  def hubspot_client
    @hubspot_client ||= HubspotClient.new
  end

  # Add this method to the HubspotBigquerySyncJob class
  def debug_record_properties(record_hash, object_type)
    return unless Rails.env.development?

    debug("DEBUG RECORD STRUCTURE FOR #{object_type.upcase}")
    debug("=============================================")

    # Log the top-level keys
    debug("Top-level keys: #{record_hash.keys.inspect}")

    # If this record has properties, explore them
    if record_hash["properties"].is_a?(Hash)
      properties = record_hash["properties"]
      debug("Properties count: #{properties.keys.size}")

      # Log a sample of property keys
      sample_keys = properties.keys.first(10)
      debug("Sample property keys: #{sample_keys.inspect}")

      # Log sample values
      sample_keys.each do |key|
        debug("  - #{key}: #{properties[key].inspect}")
      end

      # Check for properties in expanded record
      expanded = expand_properties(record_hash, object_type)
      debug("Expanded record has #{expanded.keys.size} keys")
      debug("Are properties directly in expanded record?")

      sample_keys.each do |key|
        value_in_expanded = expanded.key?(key)
        debug("  - #{key} in expanded record? #{value_in_expanded}")
      end

      # Check flattened data
      data, _ = flatten_attributes(expanded)
      debug("Flattened data has #{data.keys.size} keys")
      debug("Are properties in flattened data?")

      sample_keys.each do |key|
        value_in_data = data.key?(key)
        debug("  - #{key} in flattened data? #{value_in_data}")
      end
    else
      debug("No properties hash found in record")
    end

    debug("=============================================")
  end

  # Method to update schema for an object, based on the HubspotSchemaUpdateJob logic
  def update_schema_for_object(object_type, table, dataset, bigquery)
    Rails.logger.info("Updating schema for #{object_type} before sync")
    puts "Updating schema for #{object_type} before sync"

    begin
      # Instead of extracting properties from a sample record, directly fetch all
      # available properties for this object type from the Hubspot Properties API
      hubspot_object_type = case object_type.to_sym
      when :contacts
                              "contacts"
      when :companies
                              "companies"
      when :deals
                              "deals"
      when :tickets
                              "tickets"
      when :engagements, :call_records, :meetings
                              # These don't have direct property APIs
                              nil
      else
                              object_type.to_s.singularize
      end

      if hubspot_object_type.nil?
        # For objects that don't have a properties API, fall back to sample record approach
        return update_schema_from_sample(object_type, table, dataset, bigquery)
      end

      # Get all properties for this object type using the Properties API
      begin
        response = hubspot_client.get_properties(object_type: hubspot_object_type)

        if !response.respond_to?(:results) || response.results.empty?
          Rails.logger.info("No properties found for #{object_type} in Hubspot Properties API")
          puts "No properties found for #{object_type} in Hubspot Properties API"
          return update_schema_from_sample(object_type, table, dataset, bigquery)
        end

        properties_list = response.results

        puts "Retrieved #{properties_list.size} properties for #{object_type} from Properties API"

        # Create a schema update for each property
        schema_updates = {}

        properties_list.each do |property|
          # Skip internal/calculated properties that shouldn't be included
          next if property["hidden"] == true && !property["name"].start_with?("hs_")

          # Clean up the property name
          property_name = property["name"]
          clean_name = sanitize_field_name(property_name)

          # Determine BigQuery type based on Hubspot property type
          field_type = hubspot_to_bigquery_type(property["type"], clean_name)

          schema_updates[clean_name] = { type: field_type, mode: "NULLABLE" }
        end

        # Also add standard object fields that might not be in the properties list
        standard_fields = {
          "id" => "STRING",
          "createdAt" => "TIMESTAMP",
          "updatedAt" => "TIMESTAMP",
          "archived" => "BOOLEAN",
          "synced_at" => "TIMESTAMP"
        }

        standard_fields.each do |field_name, field_type|
          clean_name = sanitize_field_name(field_name)
          schema_updates[clean_name] = { type: field_type, mode: "NULLABLE" }
        end

        # Get existing fields
        existing_fields = collect_existing_fields(table.schema.fields).map(&:downcase)

        # Find fields to add
        fields_to_add = schema_updates.keys.select { |key| !existing_fields.include?(key.downcase) }

        if fields_to_add.empty?
          Rails.logger.info("No new fields to add to #{object_type} schema")
          puts "No new fields to add to #{object_type} schema"
        else
          Rails.logger.info("Adding #{fields_to_add.size} new fields to #{object_type} schema")
          puts "Adding #{fields_to_add.size} new fields to #{object_type} schema"
          puts "New fields to add: #{fields_to_add.first(20).join(', ')}" if fields_to_add.size > 0

          # Update the table schema
          table.schema do |schema|
            fields_to_add.each do |field_name|
              field_info = schema_updates[field_name]
              add_field_to_schema(schema, field_name, field_info)
            end
          end
        end

        # Output full schema information after update
        if Rails.env.development?
          puts "\n=== FULL SCHEMA FOR #{object_type} ===\n"
          table.reload!  # Make sure we have the latest schema

          # Get all fields in the table after the update
          field_details = []
          table.schema.fields.each do |field|
            field_details << { name: field.name, type: field.type, mode: field.mode }
          end

          # Sort fields by name for easier reading
          field_details.sort_by! { |f| f[:name] }

          # Print them nicely formatted
          puts "Field Name".ljust(50) + "Type".ljust(15) + "Mode"
          puts "-" * 75
          field_details.each do |field|
            puts "#{field[:name]}".ljust(50) + "#{field[:type]}".ljust(15) + "#{field[:mode]}"
          end
          puts "\nTotal Fields: #{field_details.size}\n"
          puts "=================================\n"
        end

        Rails.logger.info("Successfully updated schema for #{object_type}")
        puts "Successfully updated schema for #{object_type}"
      rescue => e
        Rails.logger.warn("Error using Properties API for #{object_type}: #{e.message}")
        puts "Error using Properties API for #{object_type}: #{e.message}"
        # Fall back to the sample record approach
        update_schema_from_sample(object_type, table, dataset, bigquery)
      end
    rescue => e
      error_message = "Error updating schema for #{object_type}: #{e.class} - #{e.message}"
      puts error_message
      puts e.backtrace
      Rails.logger.error(error_message)
      Rails.logger.error(e.backtrace.join("\n"))

      # Log the error but don't re-raise, so the sync can still proceed
      log_error("Hubspot Schema Update Error", error_message)
    end
  end

  # Convert Hubspot property types to BigQuery types
  def hubspot_to_bigquery_type(hubspot_type, field_name = nil)
    return "TIMESTAMP" if field_name&.end_with?("_ts") ||
                         field_name&.end_with?("date") ||
                         field_name&.include?("_date_")

    case hubspot_type
    when "number"
      "FLOAT"
    when "date", "datetime"
      "TIMESTAMP"
    when "bool", "boolean"
      "BOOLEAN"
    when "enumeration" # Select dropdowns
      "STRING"
    else # Default to STRING for most Hubspot types
      "STRING"
    end
  end

  # Fallback method to update schema based on a sample record
  def update_schema_from_sample(object_type, table, dataset, bigquery)
    puts "Falling back to sample record approach for #{object_type}"

    # Get a sample record from Hubspot
    response = hubspot_client.send("get_#{object_type}", limit: 1)

    if !response.respond_to?(:results) || response.results.empty?
      Rails.logger.info("No #{object_type} records found in Hubspot for schema update")
      puts "No #{object_type} records found in Hubspot for schema update"
      return
    end

    # Get all properties for this object type
    sample_record = response.results.first
    puts "Got sample record class: #{sample_record.class}"

    # Debug the actual structure of the sample record
    if Rails.env.development?
      puts "Sample record inspection:"
      puts "- respond_to?(:properties): #{sample_record.respond_to?(:properties)}"
      if sample_record.respond_to?(:properties)
        puts "- properties class: #{sample_record.properties.class}"
        puts "- properties respond_to?(:to_hash): #{sample_record.properties.respond_to?(:to_hash)}"
      end
      puts "- respond_to?(:to_hash): #{sample_record.respond_to?(:to_hash)}"

      if sample_record.respond_to?(:to_hash)
        sample_hash = sample_record.to_hash
        puts "- to_hash result keys: #{sample_hash.keys.join(', ')}"
        if sample_hash["properties"]
          puts "- properties in hash is a #{sample_hash["properties"].class}"
          puts "- properties keys: #{sample_hash["properties"].keys.first(5).join(', ')}..."
        end
      end
    end

    # Extract properties - try multiple approaches
    properties = nil

    # Approach 1: Direct properties method
    if sample_record.respond_to?(:properties)
      puts "Record has properties method"
      properties = sample_record.properties

      # Try to convert properties to a hash if needed
      if properties.respond_to?(:to_hash)
        properties = properties.to_hash
      end
    end

    # Approach 2: Check hash representation
    if properties.nil? && sample_record.respond_to?(:to_hash)
      sample_hash = sample_record.to_hash
      if sample_hash.is_a?(Hash) && sample_hash["properties"].is_a?(Hash)
        puts "Record has properties in hash representation"
        properties = sample_hash["properties"]
      end
    end

    # If all else fails, create some basic properties
    if properties.nil?
      if Rails.env.development?
        puts "WARNING: Could not extract properties - creating basic standard properties"
        properties = {
          "id" => "sample_id",
          "createdAt" => Time.current.iso8601,
          "updatedAt" => Time.current.iso8601
        }
      else
        Rails.logger.info("No properties found in #{object_type} record for schema update")
        puts "No properties found in #{object_type} record for schema update"
        return
      end
    end

    Rails.logger.info("Found #{properties.keys.size} properties for #{object_type} in sample record")
    puts "Found #{properties.keys.size} properties for #{object_type} in sample record"

    # Also add standard object fields
    standard_fields = {
      "id" => "STRING",
      "createdAt" => "TIMESTAMP",
      "updatedAt" => "TIMESTAMP",
      "archived" => "BOOLEAN",
      "synced_at" => "TIMESTAMP"
    }

    # Build schema updates
    schema_updates = {}
    properties.each do |prop_name, prop_value|
      # Clean up the property name
      clean_name = sanitize_field_name(prop_name)

      # Infer the BigQuery type
      field_type = infer_bigquery_type(prop_value, clean_name)

      schema_updates[clean_name] = { type: field_type, mode: "NULLABLE" }
    end

    # Add standard fields
    standard_fields.each do |field_name, field_type|
      clean_name = sanitize_field_name(field_name)
      schema_updates[clean_name] = { type: field_type, mode: "NULLABLE" }
    end

    # Get existing fields
    existing_fields = collect_existing_fields(table.schema.fields).map(&:downcase)

    # Find fields to add
    fields_to_add = schema_updates.keys.select { |key| !existing_fields.include?(key.downcase) }

    if fields_to_add.empty?
      Rails.logger.info("No new fields to add to #{object_type} schema from sample")
      puts "No new fields to add to #{object_type} schema from sample"
      return
    end

    Rails.logger.info("Adding #{fields_to_add.size} new fields to #{object_type} schema from sample")
    puts "Adding #{fields_to_add.size} new fields to #{object_type} schema from sample"

    # Update the table schema
    table.schema do |schema|
      fields_to_add.each do |field_name|
        field_info = schema_updates[field_name]
        add_field_to_schema(schema, field_name, field_info)
      end
    end

    Rails.logger.info("Successfully updated schema for #{object_type} from sample record")
    puts "Successfully updated schema for #{object_type} from sample record"
  end
end
