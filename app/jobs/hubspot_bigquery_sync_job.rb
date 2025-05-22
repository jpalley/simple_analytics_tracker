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
    contacts: { id_field: "id", supports_incremental: true },
    companies: { id_field: "id", supports_incremental: true },
    deals: { id_field: "id", supports_incremental: true },
    tickets: { id_field: "id", supports_incremental: true },
    leads: { id_field: "id", supports_incremental: true },
    owners: { id_field: "id", supports_incremental: false, uses_custom_schema: true },
    deal_pipelines: { id_field: "id", single_batch: true, supports_incremental: false, uses_custom_schema: true },
    calls: { id_field: "id", supports_incremental: true },
    emails: { id_field: "id", supports_incremental: true },
    meetings: { id_field: "id", supports_incremental: true },
    notes: { id_field: "id", supports_incremental: true }
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
      # Track the most recent modification timestamp we find
      @max_modification_time = nil

      if object_type.present?
        if HUBSPOT_OBJECTS.key?(object_type.to_sym)
          sync_object(object_type.to_sym, full_sync: full_sync)
          save_successful_sync(object_type)
        else
          log_error("Hubspot BigQuery Sync Warning", "Unknown object type: #{object_type}")
          save_error(object_type, "Unknown object type: #{object_type}")
          Rails.logger.warn("Unknown object type: #{object_type}. Available types: #{HUBSPOT_OBJECTS.keys.join(', ')}")
        end
      else
        # Sync all objects
        HUBSPOT_OBJECTS.keys.each do |object|
          begin
            sync_object(object, full_sync: full_sync)
            # Use the maximum modification time we found for the synced_at time
            # Fall back to current time if we didn't find any modification times

            # Record the success
            save_successful_sync(object)
          rescue => e
            error_message = "Error syncing object type #{object}: #{e.message}"
            log_error("Hubspot BigQuery Sync Error - #{object}", error_message)
            # Record the failure
            save_error(object, error_message)
            # Continue with next object instead of failing the entire job
            next if Rails.env.production?
            # In development, we'll raise the error for easier debugging
            raise e unless Rails.env.production?
          end
        end
      end


    rescue => e
      error_message = "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
      log_error("Hubspot BigQuery Sync Error - #{object_type || 'all'}", error_message)



      raise e
    end
  end

  private

  def save_successful_sync(object_type)
    puts "Saving successful sync for #{object_type}"
    puts "Max modification time: #{@max_modification_time}"
    sync_timestamp = @max_modification_time || Time.current
    HubspotSyncStatus.create_or_update(
      object_type: object_type.to_s,
      status: "success",
      synced_at: sync_timestamp,
      record_count: @records_processed
    )
  end

  def save_error(object_type, error_message)
    HubspotSyncStatus.create_or_update(
      object_type: object_type.to_s,
      status: "error",
      error_message: error_message
    )
  end

  # Hardcoded schema for owner objects
  def get_owner_schema
    {
      "email" => { type: "STRING", mode: "NULLABLE" },
      "type" => { type: "STRING", mode: "NULLABLE" },
      "firstName" => { type: "STRING", mode: "NULLABLE" },
      "lastName" => { type: "STRING", mode: "NULLABLE" },
      "userId" => { type: "INTEGER", mode: "NULLABLE" },
      "userIdIncludingInactive" => { type: "INTEGER", mode: "NULLABLE" },
      "teams" => { type: "STRING", mode: "NULLABLE" } # Will store JSON string representation of teams array
    }
  end

  # Hardcoded schema for deal pipeline objects
  def get_deal_pipeline_schema
    {
      "label" => { type: "STRING", mode: "NULLABLE" },
      "display_order" => { type: "INTEGER", mode: "NULLABLE" },
      "displayOrder" => { type: "INTEGER", mode: "NULLABLE" }, # Alternative naming
      "stages" => { type: "JSON", mode: "NULLABLE" } # JSON type for array of stage objects including id, label, metadata, etc.
    }
  end

  def log_error(title, message, tempfile_content = nil)
    if Rails.env.development?
      puts "Error: #{message}"
      puts "Tempfile content: #{tempfile_content}"
      # Just log to console in development
      Rails.logger.error("#{title}: #{message}")
      # Dump more info to help with debugging
      if message.include?("Hubspot API Error")
        Rails.logger.debug("API Error Details:")
        Rails.logger.debug("- Hubspot Access Token first 10 chars: #{ENV['HUBSPOT_ACCESS_TOKEN'].to_s[0..9]}")
        Rails.logger.debug("- Token length: #{ENV['HUBSPOT_ACCESS_TOKEN'].to_s.length}")
      end
    else
      # Append tempfile content to the message if available
      if tempfile_content.present?
        message = "#{message}\n\nTempfile Content Sample (first 5000 chars):\n#{tempfile_content[0..5000]}"
      end

      # Create ErrorLog record in production (which will trigger email)
      ErrorLog.create(title: title, body: message)
    end
    raise message
  end

  def sync_object(object_type, full_sync: false)
    @records_processed = 0
    # Reset the max modification time for this object
    @max_modification_time = nil

    Rails.logger.info("Syncing Hubspot #{object_type}. Full sync: #{full_sync}")
    puts "Syncing Hubspot #{object_type}. Full sync: #{full_sync}"

    # Setup BigQuery
    bigquery = initialize_bigquery_client
    dataset = initialize_bigquery_dataset(bigquery)
    table_name = "hubspot_#{object_type}"
    table = dataset.table(table_name) || create_table(dataset, table_name)

    # First update the schema to ensure all properties are included
    schema = update_schema_for_object(object_type, table, dataset, bigquery)

    # Get data and sync
    object_config = HUBSPOT_OBJECTS[object_type]

    if object_config[:single_batch]
      # For objects that are retrieved in a single API call
      records = get_object_records_single_batch(object_type)
      sync_records_to_bigquery(records, table, dataset, bigquery, object_type, schema)
    else
      # For paginated objects
      # Get the last sync time if we're doing an incremental sync
      last_sync_time = nil
      if !full_sync && object_config[:supports_incremental]
        last_sync_time = get_last_sync_time(object_type)
        Rails.logger.info("Incremental sync for #{object_type} since #{last_sync_time || 'never'}")
        puts "Incremental sync for #{object_type} since #{last_sync_time || 'never'}"
      end

      sync_paginated_records(object_type, object_config, table, dataset, bigquery, schema, last_sync_time)
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

  def sync_paginated_records(object_type, object_config, table, dataset, bigquery, schema, last_sync_time = nil)
    after = nil
    has_more = true
    batch_counter = 0
    offset = 0

    # Collect all records first
    all_records = []

    while has_more
      begin
        batch_counter += 1
        Rails.logger.info("Fetching #{object_type} batch ##{batch_counter} (after: #{after || offset})")
        puts "Fetching #{object_type} batch ##{batch_counter} (after: #{after || offset})"
        # Modern APIs support fetching recently updated records
        if last_sync_time.present? && object_config[:supports_incremental]
          # For incremental sync, use the updated_after parameter
          Rails.logger.info("Incremental sync for #{object_type} since #{last_sync_time}")
          puts "Incremental sync for #{object_type} since #{last_sync_time}"
          response = hubspot_client.send("get_#{object_type}",  after: after, updated_after: last_sync_time)
        else
          # For full sync
          Rails.logger.info("Full sync for #{object_type}")
          puts "Full sync for #{object_type}"
          response = hubspot_client.send("get_#{object_type}",  after: after)
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

        if records.present?
          # Add to our collection instead of processing immediately
          all_records.concat(records)
          @records_processed += records.size
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
        puts "ERROR=======#{error_message}"
        log_error("Hubspot BigQuery Sync Error - #{object_type} Batch ##{batch_counter}", error_message)
        # Continue with next batch instead of failing the entire job
        next
      end
    end

    # After collecting all records, process them in a single operation
    if all_records.present?
      Rails.logger.info("Processing #{all_records.size} total records for #{object_type} in a single operation")
      puts "Processing #{all_records.size} total records for #{object_type} in a single operation"
      sync_records_to_bigquery(all_records, table, dataset, bigquery, object_type, schema)
    else
      Rails.logger.info("No records found for #{object_type}")
      puts "No records found for #{object_type}"
    end
  end


  def get_object_records_single_batch(object_type)
    case object_type
    when :deal_pipelines
      response = hubspot_client.get_deal_pipelines
      # Handle the specific structure of pipelines response
      response.results.map do |pipeline|
        pipeline_data = pipeline.to_hash

        # Format stages for storage in BigQuery
        if pipeline.stages.present?
          # Convert each stage to a hash and store in the pipeline
          stages_data = pipeline.stages.map do |stage|
            stage_hash = stage.to_hash

            # Ensure IDs are integers
            stage_hash["id"] = stage_hash["id"].to_i if stage_hash["id"].present?

            # Extract metadata for easier querying if needed
            if stage_hash["metadata"].is_a?(Hash)
              stage_hash["isClosed"] = stage_hash["metadata"]["isClosed"] == "true" if stage_hash["metadata"]["isClosed"].present?
              stage_hash["probability"] = stage_hash["metadata"]["probability"].to_f if stage_hash["metadata"]["probability"].present?
            end

            stage_hash
          end

          # Store the stages in the pipeline
          # We're using JSON type in BigQuery, so we can store the array directly
          pipeline_data["stages"] = stages_data
        else
          pipeline_data["stages"] = []
        end

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

  def sync_records_to_bigquery(records, table, dataset, bigquery, object_type, schema)
    return if records.empty?

    # Process records into a format suitable for BigQuery
    processed_records = []


    records.each do |record|
      # Convert to hash if it's an object
      record_hash = record.is_a?(Hash) ? record : record.to_hash

      # Flatten the record and update schema
      data = flatten_attributes(record_hash, schema)
      # Extract the most recent modification timestamp from the record
      last_modified_time = nil
      # First check if it's in properties
      if data["hs_lastmodifieddate"].present?
        # HubSpot timestamps are in ISO8601 format like "2024-05-14T01:57:47.432Z"
        last_modified_time = Time.parse(data["hs_lastmodifieddate"]).utc.iso8601
      elsif data["lastmodifieddate"].present?
        last_modified_time = Time.parse(data["lastmodifieddate"]).utc.iso8601
      elsif data["updatedAt"].present?
        last_modified_time = Time.parse(data["updatedAt"].to_s).utc.iso8601
      end

      # Update the global max modification time if this record's time is more recent
      if last_modified_time.present?
        parsed_time = Time.parse(last_modified_time)
        @max_modification_time = parsed_time if @max_modification_time.nil? || parsed_time > @max_modification_time
      else
        puts data.inspect
      end
      processed_records << data
    end


    # Use a temp file to upload all the data at once
    Tempfile.open([ "hubspot_#{object_type}", ".json" ]) do |tempfile|
      processed_records.each do |data_row|
        tempfile.puts data_row.to_json
      end
      tempfile.flush

      # Read tempfile content for error reporting if needed
      tempfile_content = File.read(tempfile.path)

      # Create a temporary table name
      temp_table_name = "#{table.table_id}_temp_#{Time.now.to_i}"
      temp_table = dataset.table(temp_table_name) || dataset.create_table(temp_table_name) do |temp_schema|
        # Copy schema from the main table
        table.schema.fields.each do |field|
          temp_schema.send(field.type.downcase, field.name, mode: field.mode)
        end
      end

      # Load data into temp table
      load_job = temp_table.load_job tempfile, format: :json
      load_job.wait_until_done!

      if load_job.failed?
        temp_table.delete if dataset.table(temp_table_name)
        error_message = "Failed to load #{object_type} data to temp BigQuery table: #{load_job.error.inspect}\n#{load_job.errors&.inspect}"
        log_error("Hubspot BigQuery Sync Error - #{object_type}", error_message, tempfile_content)
        # Clean up temp table
        return
      end

      # Construct and run the MERGE query to perform upsert
      merge_query = <<-SQL
        MERGE `#{dataset.dataset_id}.#{table.table_id}` T
        USING `#{dataset.dataset_id}.#{temp_table_name}` S
        ON T.id = S.id
        WHEN MATCHED THEN
          UPDATE SET #{temp_table.schema.fields.map { |f| "#{f.name} = S.#{f.name}" if f.name != 'id' }.compact.join(', ')}
        WHEN NOT MATCHED THEN
          INSERT (#{temp_table.schema.fields.map(&:name).join(', ')})
          VALUES (#{temp_table.schema.fields.map { |f| "S.#{f.name}" }.join(', ')})
      SQL

      begin
        # Execute the merge query
        merge_job = bigquery.query_job(merge_query)
        merge_job.wait_until_done!

        if merge_job.failed?
          error_message = "Failed to merge #{object_type} data: #{merge_job.error.inspect}\n#{merge_job.errors&.inspect}"
          log_error("Hubspot BigQuery Sync Error - #{object_type}", error_message)
        end
      rescue => e
        error_message = "Error during merge operation for #{object_type}: #{e.message}"
        log_error("Hubspot BigQuery Sync Error - #{object_type}", error_message)
      ensure
        # Clean up temp table regardless of success or failure
        if dataset.table(temp_table_name)
          temp_table = dataset.table(temp_table_name)
          temp_table.delete
        end
      end
    end
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
      schema.integer "id", mode: "REQUIRED"
      schema.timestamp "synced_at"
      schema.timestamp "createdAt"
      schema.timestamp "updatedAt"
      schema.boolean "archived"
      # Basic schema - will be expanded dynamically
    end
  end

  # Updated flatten_attributes method to handle nested properties better
  def flatten_attributes(attributes, schema, parent_field = nil)
    data = {}

    # CRITICAL FIX: Ensure the id field is included first if present
    # if attributes.is_a?(Hash) && attributes.key?("id")
    # Convert ID to integer if schema specifies INTEGER type for id field
    # if schema["id"] && schema["id"][:type] == "INTEGER"
    # data["id"] = attributes["id"].to_i if attributes["id"].present?
    # else
    # data["id"] = attributes["id"]
    # end
    # end

    # First, handle the special case of Hubspot properties
    if attributes.is_a?(Hash) && attributes["properties"].is_a?(Hash) && parent_field.nil?
      puts "Properties is a hash"
      # Directly include all properties at the top level
      attributes["properties"].each do |prop_name, prop_value|
        clean_name = sanitize_field_name(prop_name)
        data[clean_name] = prop_value
      end
    end

    # Then process all other attributes normally
    attributes.each do |key, value|
      # Skip "properties" since we already processed it
      next if key == "properties" && value.is_a?(Hash) && parent_field.nil?
      # Skip "id" since we already processed it
      next if key == "id" && parent_field.nil?

      current_field = parent_field ? "#{parent_field}.#{key}" : key.to_s

      # Clean up field name
      field_name = sanitize_field_name(current_field)
      next if field_name.nil?

      # Skip properties_ prefix on fields that come from properties hash
      if field_name.start_with?("properties_")
        field_name = field_name.sub(/^properties_/, "")
      end
      if field_name == "id"
        data[field_name] = value.to_i
      elsif value.is_a?(Hash)
        nested_data = flatten_attributes(value, schema, key.to_s)
        data.merge!(nested_data)
      elsif value.is_a?(Array)
        # Handle array values based on schema type
        if schema[field_name] && schema[field_name][:type] == "JSON"
          # For JSON fields, keep the array as-is without converting to string
          # For stages, ensure stage IDs are integers
          if field_name == "stages"
            value.each do |stage|
              if stage.is_a?(Hash) && stage["id"].present?
                stage["id"] = stage["id"].to_i
              end
            end
          end
          data[field_name] = value
        else
          # For other fields, convert to JSON string
          if value.any?
            data[field_name] = JSON.generate(value)
          else
            data[field_name] = "[]"
          end
        end
      elsif schema[field_name] && schema[field_name][:type] == "TIMESTAMP" && value.present? && value.is_a?(String)
          data[field_name] = Time.parse(value).utc.iso8601.to_s
      else
        # Handle primitive values
        data[field_name] = value
      end
    end

    data["synced_at"] = Time.now.utc.iso8601

    data
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
    # Handle JSON type separately as it needs special handling
    if field_info[:type] == "JSON"
      schema.json field_name, mode: field_info[:mode]
    else
      schema.send(
        field_info[:type].downcase,
        field_name,
        mode: field_info[:mode]
      )
    end
  end



  def hubspot_client
    @hubspot_client ||= HubspotClient.new
  end

  # Method to update schema for an object, based on the HubspotSchemaUpdateJob logic
  def update_schema_for_object(object_type, table, dataset, bigquery)
    Rails.logger.info("Updating schema for #{object_type} before sync")
    puts "Updating schema for #{object_type} before sync"

    begin
      # Use hardcoded schema for objects with custom schema
      schema_updates = if HUBSPOT_OBJECTS[object_type][:uses_custom_schema]
        # Select the appropriate schema based on object type
        case object_type
        when :owners
          get_owner_schema
        when :deal_pipelines
          get_deal_pipeline_schema
        else
          # Add methods for other custom schemas as needed
          raise "Custom schema flag set for #{object_type} but no custom schema method available"
        end
      else
        # Get all property definitions for this object type from the Hubspot Client
        property_definitions = hubspot_client.get_all_property_definitions(object_type)


        puts "Retrieved #{property_definitions.size} property definitions for #{object_type}"

        # Create a schema update for each property
        schema_updates = {}

        property_definitions.each do |property_name, property_definition|
          next unless property_definition.is_a?(Hash) # Ensure it's a hash

          clean_name = sanitize_field_name(property_name)
          hubspot_type = property_definition["type"] # e.g., 'string', 'number', 'date'

          # Get the BigQuery type using the new mapping method
          field_type = map_hubspot_type_to_bigquery_type(hubspot_type, property_name)

          schema_updates[clean_name] = { type: field_type, mode: "NULLABLE" }
        end

        # Ensure 'id' is REQUIRED if it's the primary key
        if schema_updates["id"]
           schema_updates["id"][:mode] = "REQUIRED"
        else # if no hubspot property is named id, add it as required
           schema_updates["id"] = { type: "INTEGER", mode: "REQUIRED" }
        end

        schema_updates
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
      table.reload!
      schema = {}
      table.schema.fields.each do |field|
        schema[field.name] = { type: field.type, mode: field.mode }
      end

      # Output full schema information after update
      if Rails.env.development?
        puts "\n=== FULL SCHEMA FOR #{object_type} ===\n"
        table.reload! # Make sure we have the latest schema

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
      error_message = "Error updating schema for #{object_type}: #{e.class} - #{e.message}"
      puts error_message
      puts e.backtrace
      Rails.logger.error(error_message)
      Rails.logger.error(e.backtrace.join("\n"))

      # Log the error but don't re-raise, so the sync can still proceed
      log_error("Hubspot Schema Update Error", error_message)
    end

    schema
  end

  # Convert Hubspot property type string to BigQuery type string.
  # field_name is optional and can be used for nuanced decisions if direct type mapping isn't enough.
  def map_hubspot_type_to_bigquery_type(hubspot_type_string, field_name = nil)
    # Based on HubSpot documentation for property field types:
    # Common types: string, number, date, datetime, bool, enumeration
    case hubspot_type_string&.downcase
    when "string", "phone_number", "enumeration"
      # enumeration is for dropdowns, typically stored as strings
      "STRING"
    when "number"
      # HubSpot 'number' type can be integer or float.
      # For BigQuery, FLOAT (FLOAT64) is safer to accommodate both.
      # If specific integer properties are known, this could be refined.
      # Checking field_name for "id" or "count" could indicate INTEGER.
      if field_name&.downcase&.end_with?("id", "_id", "count")
        "INTEGER"
      else
        "FLOAT" # Default 'number' to FLOAT
      end
    when "date", "datetime"
      "TIMESTAMP"
    when "bool", "boolean" # HubSpot uses 'bool'
      "BOOLEAN"
    # Add other HubSpot types if they exist and need specific mapping
    # e.g., "json", "currency", etc.
    else
      # Fallback for unknown or unhandled HubSpot types.

      # during data processing, but for schema definition, STRING is safest.
      Rails.logger.warn("Unknown or unhandled HubSpot property type: '#{hubspot_type_string}' for field '#{field_name}'. Defaulting to STRING.")
      "STRING"
    end
  end
end
