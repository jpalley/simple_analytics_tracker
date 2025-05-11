namespace :hubspot do
  desc "Run Hubspot to BigQuery sync with automatic schema updates"
  task :sync, [ :object_type, :full_sync ] => :environment do |t, args|
    # Require the job class
    require_relative "../../app/jobs/hubspot_bigquery_sync_job"
    require_relative "../../app/services/hubspot_client"

    # Set default values
    object_type = args[:object_type]
    full_sync = args[:full_sync] == "true"

    puts "Starting Hubspot sync for #{object_type || 'all objects'} (Full sync: #{full_sync})"

    begin
      # Run the job
      job = HubspotBigquerySyncJob.new
      job.perform(object_type, full_sync: full_sync)
      puts "Sync completed successfully"
    rescue => e
      puts "Error in HubspotBigquerySyncJob: #{e.class} - #{e.message}"
      puts e.backtrace
      raise e
    end
  end

  desc "Update BigQuery schema for Hubspot objects"
  task :update_schema, [ :object_type ] => :environment do |t, args|
    # Require the job class
    require_relative "../../app/jobs/hubspot_bigquery_sync_job"
    require_relative "../../app/services/hubspot_client"

    # Set default values
    object_type = args[:object_type]

    puts "Starting Hubspot schema update for #{object_type || 'all objects'}"

    begin
      # Object types to process
      object_types = if object_type.present?
                      [ object_type.to_sym ]
      else
                      [ :contacts, :companies, :deals, :tickets, :owners, :engagements, :deal_pipelines, :deal_stages ]
      end

      # Setup BigQuery
      bigquery = initialize_bigquery_client
      dataset = initialize_bigquery_dataset(bigquery)

      object_types.each do |type|
        puts "Updating schema for #{type}"

        # Get table
        table_name = "hubspot_#{type}"
        table = dataset.table(table_name)

        unless table
          puts "Table #{table_name} does not exist. Skipping."
          next
        end

        # Update schema for this object type
        job = HubspotBigquerySyncJob.new
        job.send(:update_schema_for_object, type, table, dataset, bigquery)
      end

      puts "Schema updates completed successfully"
    rescue => e
      puts "Error in schema update: #{e.class} - #{e.message}"
      puts e.backtrace
      raise e
    end
  end

  desc "Update BigQuery schema for Hubspot objects directly"
  task :direct_schema_update, [ :object_type ] => :environment do |t, args|
    require "google/cloud/bigquery"
    require "json"
    require_relative "../../app/services/hubspot_client"

    # Set default values
    object_type = args[:object_type]

    puts "Starting direct Hubspot schema update for #{object_type || 'all objects'}"

    # Helper methods defined inside the task
    def update_schema_for_object(object_type, table, dataset, bigquery)
      puts "Direct schema update for #{object_type}"

      # Get a sample record from Hubspot
      client = HubspotClient.new
      begin
        response = client.send("get_#{object_type}", limit: 1)
      rescue => e
        puts "Error getting sample #{object_type} record: #{e.message}"
        return
      end

      if !response.respond_to?(:results) || response.results.empty?
        puts "No #{object_type} records found in Hubspot"
        return
      end

      # Get all properties for this object type
      sample_record = response.results.first
      puts "Got sample record class: #{sample_record.class}"

      # Convert to hash if it's an object
      properties = nil

      # For Hubspot objects like SimplePublicObjectWithAssociations
      if sample_record.respond_to?(:properties)
        puts "Record has properties attribute"
        properties = sample_record.properties

        # Try to convert properties to a hash if it's an object
        if properties.respond_to?(:to_hash)
          properties = properties.to_hash
        end
      elsif sample_record.respond_to?(:to_hash)
        sample_record_hash = sample_record.to_hash
        if sample_record_hash["properties"].is_a?(Hash)
          puts "Record has properties key in hash"
          properties = sample_record_hash["properties"]
        end
      elsif sample_record.is_a?(Hash) && sample_record["properties"].is_a?(Hash)
        puts "Record is already a hash with properties key"
        properties = sample_record["properties"]
      end

      unless properties.is_a?(Hash)
        puts "Could not find valid properties for #{object_type}"
        puts "Record: #{sample_record.inspect}"
        return
      end

      puts "Found #{properties.keys.size} properties for #{object_type}"

      # Build schema updates
      schema_updates = {}
      properties.each do |prop_name, prop_value|
        # Clean up the property name
        clean_name = sanitize_field_name(prop_name)

        # Infer the BigQuery type
        field_type = infer_bigquery_type(prop_value)

        schema_updates[clean_name] = { type: field_type, mode: "NULLABLE" }
      end

      # Get existing fields
      existing_fields = collect_existing_fields(table.schema.fields).map(&:downcase)

      # Find fields to add
      fields_to_add = schema_updates.keys.select { |key| !existing_fields.include?(key.downcase) }

      if fields_to_add.empty?
        puts "No new fields to add to #{object_type} schema"
        return
      end

      puts "Adding #{fields_to_add.size} new fields to #{object_type} schema"
      puts "New fields: #{fields_to_add.join(', ')}"

      # Update the table schema
      table.schema do |schema|
        fields_to_add.each do |field_name|
          field_info = schema_updates[field_name]
          schema.send(
            field_info[:type].downcase,
            field_name,
            mode: field_info[:mode]
          )
        end
      end

      puts "Successfully updated schema for #{object_type}"
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
      when Time, DateTime
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

    begin
      # Object types to process
      object_types = if object_type.present?
                      [ object_type.to_sym ]
      else
                      [ :contacts, :companies, :deals, :tickets, :owners, :engagements, :deal_pipelines, :deal_stages ]
      end

      # Setup BigQuery
      bigquery = initialize_bigquery_client
      dataset = initialize_bigquery_dataset(bigquery)

      object_types.each do |type|
        puts "Updating schema for #{type}"

        # Get table
        table_name = "hubspot_#{type}"
        table = dataset.table(table_name)

        unless table
          puts "Table #{table_name} does not exist. Skipping."
          next
        end

        # Update schema directly
        update_schema_for_object(type, table, dataset, bigquery)
      end

      puts "Schema updates completed successfully"
    rescue => e
      puts "Error in schema update: #{e.class} - #{e.message}"
      puts e.backtrace
      raise e
    end
  end

  desc "All-in-one update schema and sync for Hubspot data"
  task :standalone_sync, [ :object_type, :full_sync ] => :environment do |t, args|
    require "google/cloud/bigquery"
    require "json"
    require_relative "../../app/services/hubspot_client"

    # Set default values
    object_type = args[:object_type]
    full_sync = args[:full_sync] == "true"

    puts "Starting standalone Hubspot sync for #{object_type || 'all objects'} (Full sync: #{full_sync})"

    # Helper methods
    def update_schema_for_object(object_type, table, dataset, bigquery)
      puts "Updating schema for #{object_type}"

      # Get a sample record from Hubspot
      client = HubspotClient.new
      begin
        response = client.send("get_#{object_type}", limit: 1)
      rescue => e
        puts "Error getting sample #{object_type} record: #{e.message}"
        return
      end

      if !response.respond_to?(:results) || response.results.empty?
        puts "No #{object_type} records found in Hubspot"
        return
      end

      # Get all properties for this object type
      sample_record = response.results.first
      puts "Got sample record class: #{sample_record.class}"

      # Convert to hash if it's an object
      properties = nil

      # For Hubspot objects like SimplePublicObjectWithAssociations
      if sample_record.respond_to?(:properties)
        puts "Record has properties attribute"
        properties = sample_record.properties

        # Try to convert properties to a hash if it's an object
        if properties.respond_to?(:to_hash)
          properties = properties.to_hash
        end
      elsif sample_record.respond_to?(:to_hash)
        sample_record_hash = sample_record.to_hash
        if sample_record_hash["properties"].is_a?(Hash)
          puts "Record has properties key in hash"
          properties = sample_record_hash["properties"]
        end
      elsif sample_record.is_a?(Hash) && sample_record["properties"].is_a?(Hash)
        puts "Record is already a hash with properties key"
        properties = sample_record["properties"]
      end

      unless properties.is_a?(Hash)
        puts "Could not find valid properties for #{object_type}"
        puts "Record: #{sample_record.inspect}"
        return
      end

      puts "Found #{properties.keys.size} properties for #{object_type}"

      # Build schema updates
      schema_updates = {}
      properties.each do |prop_name, prop_value|
        # Clean up the property name
        clean_name = sanitize_field_name(prop_name)

        # Infer the BigQuery type
        field_type = infer_bigquery_type(prop_value)

        schema_updates[clean_name] = { type: field_type, mode: "NULLABLE" }
      end

      # Get existing fields
      existing_fields = collect_existing_fields(table.schema.fields).map(&:downcase)

      # Find fields to add
      fields_to_add = schema_updates.keys.select { |key| !existing_fields.include?(key.downcase) }

      if fields_to_add.empty?
        puts "No new fields to add to #{object_type} schema"
        return
      end

      puts "Adding #{fields_to_add.size} new fields to #{object_type} schema"
      puts "New fields: #{fields_to_add.join(', ')}"

      # Update the table schema
      begin
        table.schema do |schema|
          fields_to_add.each do |field_name|
            field_info = schema_updates[field_name]
            schema.send(
              field_info[:type].downcase,
              field_name,
              mode: field_info[:mode]
            )
          end
        end
        puts "Successfully updated schema for #{object_type}"
      rescue => e
        puts "Error updating schema: #{e.message}"
      end
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
      when Time, DateTime
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

    def sync_hubspot_data(object_type, table, bigquery, full_sync)
      puts "Syncing Hubspot data for #{object_type} (full_sync: #{full_sync})"
      client = HubspotClient.new

      # Determine if we need to do an incremental sync
      last_sync_time = nil
      supports_incremental = [ :contacts, :companies, :deals, :tickets, :engagements, :call_records, :meetings ].include?(object_type.to_sym)

      if !full_sync && supports_incremental
        # Get the last successful sync time for this object type
        puts "Getting last sync time for #{object_type}"
        last_sync = HubspotSyncStatus.last_successful_sync(object_type.to_s)

        if last_sync&.synced_at
          last_sync_time = last_sync.synced_at.iso8601
          puts "Last sync time: #{last_sync_time}"
        else
          puts "No previous successful sync found"
        end
      end

      # Get the data from Hubspot
      records = []
      record_count = 0

      # Handle different object types
      case object_type.to_sym
      when :deal_pipelines, :deal_stages, :properties
        # Single batch objects
        if object_type.to_sym == :deal_pipelines
          response = client.get_deal_pipelines
          records = response.results.map(&:to_hash)
        elsif object_type.to_sym == :deal_stages
          response = client.get_deal_stages
          records = response.results
        elsif object_type.to_sym == :properties
          # Properties for each object type
          property_groups = [ "contacts", "companies", "deals", "tickets" ]
          all_properties = []

          property_groups.each do |group|
            response = client.get_properties(object_type: group)
            properties = response.results.map do |prop|
              prop_hash = prop.is_a?(Hash) ? prop : prop.to_hash
              prop_hash["object_type"] = group
              prop_hash
            end
            all_properties.concat(properties)
          end
          records = all_properties
        end

        # Process records
        puts "Got #{records.size} records"
        record_count = records.size
      else
        # Paginated objects
        has_more = true
        after = nil
        offset = 0 # For legacy APIs
        page = 1
        limit = 100

        while has_more && page <= 10 # Limit to 10 pages for safety
          puts "Fetching page #{page} (after: #{after}, offset: #{offset})"

          if [ :engagements, :workflows, :lists, :call_records ].include?(object_type.to_sym)
            # Legacy APIs
            response = client.send("get_#{object_type}", limit: limit, offset: offset)

            # Get records, handle different response formats
            if response.is_a?(Hash) && response["results"]
              page_records = response["results"]
            elsif response.respond_to?(:results)
              page_records = response.results
            else
              page_records = []
            end

            # Get pagination info
            if response.is_a?(Hash)
              offset = response["offset"] if response["offset"]
              has_more = response["hasMore"] if response.key?("hasMore")
            elsif response.respond_to?(:offset)
              offset = response.offset
              has_more = response.respond_to?(:hasMore) ? response.hasMore : false
            else
              has_more = false
            end
          else
            # Modern APIs
            begin
              if last_sync_time.present? && supports_incremental
                # Use the proper method for incremental syncing - this varies by object
                modified_date_property = object_type.to_sym == :contacts ? "lastmodifieddate" : "hs_lastmodifieddate"

                # Use the client method instead of constructing the request ourselves
                response = client.send("get_#{object_type}", limit: limit, after: after, updated_after: last_sync_time)
              else
                # For full sync
                response = client.send("get_#{object_type}", limit: limit, after: after)
              end

              # Get records
              if response.respond_to?(:results)
                page_records = response.results
              elsif response.is_a?(Hash) && response["results"]
                page_records = response["results"]
              else
                puts "Unexpected response format: #{response.class}"
                page_records = []
              end

              # Get pagination info
              if response.respond_to?(:paging) && response.paging
                after = response.paging.next&.after if response.paging.respond_to?(:next)
                has_more = after.present?
              elsif response.is_a?(Hash) && response["paging"]
                after = response["paging"]["next"]["after"] rescue nil
                has_more = after.present?
              else
                has_more = false
              end
            rescue => e
              puts "Error fetching page #{page} for #{object_type}: #{e.class} - #{e.message}"
              break
            end
          end

          # Process the page of records
          if page_records && !page_records.empty?
            puts "Got #{page_records.size} records on page #{page}"

            page_records.each do |record|
              # Convert to hash if needed
              record_hash = nil
              if record.respond_to?(:to_hash)
                record_hash = record.to_hash
              elsif record.is_a?(Hash)
                record_hash = record
              else
                # Try to extract data from the record object
                puts "Converting record of type: #{record.class}"
                record_hash = {}

                # For objects with id and properties
                if record.respond_to?(:id)
                  record_hash["id"] = record.id
                end

                if record.respond_to?(:properties)
                  record_hash["properties"] = record.properties.respond_to?(:to_hash) ? record.properties.to_hash : record.properties
                end

                if record.respond_to?(:created_at)
                  record_hash["createdAt"] = record.created_at
                end

                if record.respond_to?(:updated_at)
                  record_hash["updatedAt"] = record.updated_at
                end
              end

              if record_hash
                records << record_hash
              else
                puts "Could not convert record to hash: #{record.class}"
              end
            end
          else
            puts "No records returned or empty response"
            has_more = false
          end

          page += 1
        end

        record_count = records.size
        puts "Total records fetched: #{record_count}"
      end

      # Write to BigQuery
      if records.empty?
        puts "No records to sync"
        return 0
      end

      # Process records for BigQuery
      puts "Processing #{records.size} records for BigQuery"
      processed_records = []
      schema = {}

      records.each do |record|
        # Add timestamp field
        record[:synced_at] = Time.current.utc.iso8601

        # Expand properties
        expanded = expand_properties(record, object_type)

        # Flatten data
        data, record_schema = flatten_attributes(expanded)
        processed_records << data
        schema.merge!(record_schema) { |_key, old_val, new_val| merge_schemas(old_val, new_val) }
      end

      # Update table schema if needed
      update_table_schema(table, schema)

      # Write data to BigQuery
      puts "Writing #{processed_records.size} records to BigQuery"

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
          puts "Failed to load data to BigQuery: #{load_job.error}"
          return 0
        end
      end

      puts "Successfully loaded #{processed_records.size} records to BigQuery"
      processed_records.size
    end

    def expand_properties(record, object_type)
      expanded = record.dup

      # Handle Hubspot API objects
      if !expanded.is_a?(Hash) && expanded.respond_to?(:to_hash)
        expanded = expanded.to_hash
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

          # Keep the original properties hash for reference
          expanded["all_properties"] = properties
        end
      end

      expanded
    end

    def flatten_attributes(attributes)
      data = {}
      schema = {}

      # First, directly include properties
      if attributes.is_a?(Hash) && attributes["properties"].is_a?(Hash)
        attributes["properties"].each do |prop_name, prop_value|
          field_name = sanitize_field_name(prop_name)
          data[field_name] = prop_value
          schema[field_name] = { type: infer_bigquery_type(prop_value), mode: "NULLABLE" }
        end
      end

      # Then process all other fields
      attributes.each do |key, value|
        # Skip properties since we already processed it
        next if key == "properties"

        field_name = sanitize_field_name(key.to_s)

        if value.is_a?(Hash)
          # Convert hash to JSON for BigQuery
          data[field_name] = JSON.generate(value)
          schema[field_name] = { type: "STRING", mode: "NULLABLE" }
        elsif value.is_a?(Array)
          # Convert array to JSON for BigQuery
          data[field_name] = JSON.generate(value)
          schema[field_name] = { type: "STRING", mode: "NULLABLE" }
        else
          # Handle primitive values
          data[field_name] = value
          schema[field_name] = { type: infer_bigquery_type(value), mode: "NULLABLE" }
        end
      end

      [ data, schema ]
    end

    def update_table_schema(table, data_schema)
      existing_fields = collect_existing_fields(table.schema.fields).map(&:downcase)
      new_fields = data_schema.keys.select { |key| !existing_fields.include?(key.downcase) }

      return if new_fields.empty?

      puts "Adding #{new_fields.size} new fields to table schema"

      table.schema do |schema|
        new_fields.each do |field_name|
          field_info = data_schema[field_name]
          schema.send(
            field_info[:type].downcase,
            field_name,
            mode: field_info[:mode]
          )
        end
      end
    end

    def merge_schemas(old_val, new_val)
      if old_val.is_a?(Hash) && new_val.is_a?(Hash)
        old_val.merge(new_val) { |_key, old_subval, new_subval| merge_schemas(old_subval, new_subval) }
      else
        new_val
      end
    end

    begin
      # Setup BigQuery
      begin
        bigquery = initialize_bigquery_client
        dataset = initialize_bigquery_dataset(bigquery)
      rescue => e
        puts "Error initializing BigQuery: #{e.message}"
        raise
      end

      # Object types to process
      object_types = if object_type.present?
                      [ object_type.to_sym ]
      else
                      [ :contacts, :companies, :deals, :tickets, :owners, :engagements, :deal_pipelines, :deal_stages ]
      end

      # Process each object type
      records_processed = 0

      object_types.each do |type|
        puts "Processing #{type}"

        # Create or get table
        table_name = "hubspot_#{type}"
        table = dataset.table(table_name)

        # Create table if it doesn't exist
        unless table
          puts "Creating table #{table_name}"
          table = dataset.create_table(table_name) do |schema|
            schema.string "id", mode: "REQUIRED"
            schema.timestamp "synced_at"
          end
        end

        # First update schema
        update_schema_for_object(type, table, dataset, bigquery)

        # Then sync data
        type_records = sync_hubspot_data(type, table, bigquery, full_sync)
        records_processed += type_records

        # Update sync status
        HubspotSyncStatus.create_or_update(
          object_type: type.to_s,
          status: "success",
          record_count: type_records,
          synced_at: Time.current
        )

        puts "Completed sync for #{type} - #{type_records} records"
      end

      puts "All syncs completed - total #{records_processed} records processed"

    rescue => e
      puts "Error in standalone sync: #{e.class} - #{e.message}"
      puts e.backtrace

      # Record the error
      if object_type.present?
        HubspotSyncStatus.create_or_update(
          object_type: object_type,
          status: "error",
          error_message: "#{e.class}: #{e.message}"
        )
      end

      raise e
    end
  end

  private

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
        puts "Error parsing GOOGLE_CLOUD_CREDENTIALS: #{e.message}. Trying alternative format."

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
  end

  def initialize_bigquery_dataset(bigquery)
    dataset_id = ENV["BIGQUERY_DATASET"]
    dataset = bigquery.dataset(dataset_id)

    unless dataset
      puts "Creating BigQuery dataset: #{dataset_id}"
      dataset = bigquery.create_dataset(dataset_id)
    end

    dataset
  end
end
