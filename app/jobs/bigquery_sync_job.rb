# app/jobs/bigquery_sync_job.rb

require "google/cloud/bigquery"
require "json"
require "tempfile"

class BigquerySyncJob < ApplicationJob
  queue_as :default

  def perform
    begin
      # Initialize BigQuery client (project_id and credentials are set globally)
      if Rails.env.development?
        bigquery = Google::Cloud::Bigquery.new(
          project: ENV["GOOGLE_CLOUD_PROJECT"],
        # credentials: JSON.parse(ENV["GOOGLE_CLOUD_CREDENTIALS"].gsub(/(?<!\\)(\\n)/, "").gsub('\n', "n"))
        credentials: JSON.parse(ENV["GOOGLE_CLOUD_CREDENTIALS"])
        )
      else
        bigquery = Google::Cloud::Bigquery.new(
          project: ENV["GOOGLE_CLOUD_PROJECT"],
        credentials: JSON.parse(ENV["GOOGLE_CLOUD_CREDENTIALS"].gsub(/(?<!\\)(\\n)/, "").gsub('\n', "n")),
        timeout: 1200,
        retries: 3
        # credentials: JSON.parse(ENV["GOOGLE_CLOUD_CREDENTIALS"])
      )
      end

      dataset_id = ENV["BIGQUERY_DATASET"]
      dataset = bigquery.dataset(dataset_id) || bigquery.create_dataset(dataset_id)

      # Sync Persons
      bulk_sync_persons(bigquery, dataset)

      # Sync Events
      bulk_sync_events(bigquery, dataset)
    rescue => e
      ErrorLog.create(title: "BigQuery Sync Job Error for #{job_id}, Enqueued at: #{enqueued_at}", body: e.inspect)
      raise e
    end
  end

  private

  def bulk_sync_persons(bigquery, dataset)
    persons_table = dataset.table("web_persons") || create_persons_table(dataset)

    # Select Person records that need to be upserted
    unsynced_persons = Person.where("synced IS NULL OR synced = ? OR synced_at IS NULL OR updated_at >= synced_at", false)

    if unsynced_persons.any?
      # Generate temporary table name
      temp_table_id = "persons_temp_#{Time.now.to_i}"
      # Create temp table without expiration time
      temp_table = dataset.create_table(temp_table_id)

      # Set expiration time using ALTER TABLE
      expiration_timestamp = (Time.now + 3600).utc.strftime("%Y-%m-%d %H:%M:%S UTC")
      alter_table_sql = <<~SQL
        ALTER TABLE `#{dataset.dataset_id}.#{temp_table.table_id}`
          SET OPTIONS (
            expiration_timestamp = TIMESTAMP "#{expiration_timestamp}"
        )
      SQL

      bigquery.query alter_table_sql

      # Reload temp_table to get updated metadata
      temp_table = dataset.table(temp_table.table_id)

      person_data = []
      person_schema = {}

      unsynced_persons.find_each(batch_size: 10000) do |person|
        data, schema = flatten_attributes(person_attributes(person))
        person_data << data
        person_schema.merge!(schema) { |_key, old_val, new_val| merge_schemas(old_val, new_val) }
      end

      # Update schemas for both tables
      update_table_schema(temp_table, person_schema)
      update_table_schema(persons_table, person_schema)

      # Insert data into temp table

      Tempfile.open([ "persons", ".json" ]) do |tempfile|
        person_data.each do |data_row|
          formatted_row = data_row
          tempfile.puts formatted_row.to_json
        end
        tempfile.flush


        load_job = temp_table.load_job tempfile, format: :json
        # Wait for the load job to complete
        load_job.wait_until_done!

        if load_job.failed?
          ErrorLog.create(
            title: "Failed to load person data. Job ID: #{job_id}, Enqueued at: #{enqueued_at}",
            body: "BigQuery Load Job Error: #{load_job.error.inspect}"
          )
          raise "Failed to load data into BigQuery. Job ID: #{job_id}, Error: #{load_job.error} | #{load_job.errors.inspect}"
          return
        end
      end

      puts "PERFORMING MERGE"
      # Perform MERGE operation
      merge_persons_table(bigquery, dataset, temp_table, persons_table, person_schema)

      # Delete the temp table
      temp_table.delete

      # Update synced and synced_at
      unsynced_persons.update_all(synced: true, synced_at: Time.current)
    end
  end

  def bulk_sync_events(bigquery, dataset)
    events_table = dataset.table("web_events") || create_events_table(dataset)


    # Collect unsynced events
    unsynced_events = Event.where(synced: [ nil, false ])
    batch_size = 10_000 # Adjust as needed

    unsynced_events.find_in_batches(batch_size: batch_size) do |events_batch|
      # Prepare data and schema
      event_data = []
      event_schema = {}

      events_batch.each do |event|
        data, schema = flatten_attributes(event_attributes(event))
        event_data << data
        event_schema.merge!(schema) { |_key, old_val, new_val| merge_schemas(old_val, new_val) }
      end

      # Update table schema to accommodate new fields
      update_table_schema(events_table, event_schema)
      puts "event_schema: #{event_schema.inspect}"
      # Write data to temporary file
      Tempfile.open([ "events", ".json" ]) do |tempfile|
        event_data.each do |data_row|
          formatted_row = data_row
          tempfile.puts formatted_row.to_json
        end
        tempfile.flush


        load_job = events_table.load_job tempfile, format: :json
        # Wait for the load job to complete
        load_job.wait_until_done!

        if load_job.failed?
          ErrorLog.create(
            title: "Failed to load event data. Job ID: #{job_id}, Enqueued at: #{enqueued_at}",
            body: "BigQuery Load Job Error: #{load_job.error.inspect}"
          )
          raise "Failed to load data into BigQuery. Job ID: #{job_id}, Error: #{load_job.error} | #{load_job.errors.inspect}"
          return
        else
          # Update events as synced
          event_ids = events_batch.map(&:id)
          Event.where(id: event_ids).update_all(synced: true, synced_at: Time.current)
        end

        # Delete the file from GCS
      end
    end
  end

  def person_attributes(person)
    {
      "uuid" => person.uuid,
      "created_at" => person.created_at,
      "updated_at" => person.updated_at,
      "properties" => person.properties,
      "initial_params" => person.initial_params,
      "latest_params" => person.latest_params
    }
  end

  def event_attributes(event)
    {
      "uuid" => event.uuid,
      "event_type" => event.event_type,
      "timestamp" => event.timestamp,
      "created_at" => event.created_at,
      "updated_at" => event.updated_at,
      "event_data" => event.event_data
    }
  end

  # Updated flatten_attributes method
  def flatten_attributes(attributes, parent_field = nil)
    data = {}
    schema = {}

    attributes.each do |key, value|
      current_field = parent_field ? "#{parent_field}.#{key}" : key

      # Determine if we need to include the parent_field in the key
      if %w[initial_params latest_params].include?(parent_field)
        # Include parent_field with an underscore
        field_name = "#{parent_field}_#{key}"
      elsif %w[event_data properties].include?(parent_field)
        # Do not include parent_field in the key
        field_name = key
      else
        # For other fields, include the full nested field
        field_name = current_field
      end

      field_name = sanitize_field_name(field_name)

      next if field_name.nil?

      if value.is_a?(Hash)
        nested_data, nested_schema = flatten_attributes(value, key)
        data.merge!(nested_data)
        schema.merge!(nested_schema) { |_k, old_val, new_val| merge_schemas(old_val, new_val) }
      elsif value.is_a?(Array)
        array_element_type = infer_bigquery_type(value.first, field_name)
        data[field_name] = value
        schema[field_name] = { type: array_element_type, mode: "REPEATED" }
      else
        data[field_name] = value
        schema[field_name] = { type: infer_bigquery_type(value, field_name), mode: "NULLABLE" }
      end
    end

    [ data, schema ]
  end

  # Helper method to sanitize field names
  def sanitize_field_name(field_name)
    # Replace any invalid characters with underscores
    sanitized = field_name.gsub(/[^a-zA-Z0-9_]/, "_")

    # Ensure the field name starts with a letter or underscore
    sanitized = "A#{sanitized}" unless sanitized.match?(/^[a-zA-Z_]/)
    sanitized_field_name = sanitized.gsub("initial_params_", "").gsub("latest_params_", "").gsub("all_params_", "").gsub("browser_", "").gsub("selected_params_", "")
    if sanitized_field_name.length > 25
      Rails.logger.warn "Skipping field '#{sanitized_field_name}' as it exceeds 25 characters"

        return nil
    end


    sanitized
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
    if field_name.include?(".")
      # Handle nested fields
      top_field, rest = field_name.split(".", 2)
      existing_field = schema.fields.find { |f| f.name == top_field }

      if existing_field
        if existing_field.type == "RECORD"
          add_field_to_schema(existing_field, rest, field_info)
        else
          # Conflict: existing field is not a RECORD
          Rails.logger.error "Schema conflict: trying to add nested field '#{rest}' to non-RECORD field '#{top_field}'"
        end
      else
        # Create new RECORD field
        schema.record top_field, mode: "NULLABLE" do |nested_schema|
          add_field_to_schema(nested_schema, rest, field_info)
        end
      end
    else
      # Check length only for the actual field being added
      # Add field at current level
      if field_info[:type] == "RECORD"
        schema.record field_name, mode: field_info[:mode] do |nested_schema|
          field_info[:fields].each do |nested_field_name, nested_field_info|
            add_field_to_schema(nested_schema, nested_field_name, nested_field_info)
          end
        end
      else
        schema.send(
          field_info[:type].downcase,
          field_name,
          mode: field_info[:mode]
        )
      end
    end
  end

  def merge_persons_table(bigquery, dataset, temp_table, persons_table, person_schema)
    all_fields = person_schema.keys.map { |k| "`#{k}`" }
    set_clause = person_schema.keys.map { |k| "`#{k}` = SOURCE.`#{k}`" }.join(", ")
    insert_fields = all_fields.join(", ")
    insert_values = all_fields.map { |k| "SOURCE.#{k}" }.join(", ")

    merge_sql = <<~SQL
      MERGE `#{dataset.dataset_id}.#{persons_table.table_id}` AS TARGET
      USING `#{dataset.dataset_id}.#{temp_table.table_id}` AS SOURCE
      ON TARGET.uuid = SOURCE.uuid
      WHEN MATCHED THEN
        UPDATE SET #{set_clause}
      WHEN NOT MATCHED THEN
        INSERT (#{insert_fields})
        VALUES (#{insert_values})
    SQL

    # Execute the MERGE statement
    bigquery.query merge_sql
  end

  def infer_bigquery_type(value, field_name)
    # Return TIMESTAMP if field_name ends with "_ts"
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
      infer_bigquery_type(value.first)
    else
      "STRING"
    end
  end

  def create_persons_table(dataset)
    dataset.create_table("web_persons") do |schema|
      schema.string "uuid", mode: "REQUIRED"
      schema.timestamp "created_at"
      schema.timestamp "updated_at"
      # Initial schema can be minimal; fields will be added dynamically
    end
  end

  def create_events_table(dataset)
    dataset.create_table("web_events") do |schema|
      schema.string "uuid", mode: "REQUIRED"
      schema.string "event_type", mode: "REQUIRED"
      schema.timestamp "timestamp", mode: "REQUIRED"
      schema.timestamp "created_at"
      schema.timestamp "updated_at"
      # Initial schema can be minimal; fields will be added dynamically
    end
  end

  # Helper method to merge schemas correctly
  def merge_schemas(old_val, new_val)
    if old_val.is_a?(Hash) && new_val.is_a?(Hash)
      old_val.merge(new_val) { |_key, old_subval, new_subval| merge_schemas(old_subval, new_subval) }
    else
      new_val
    end
  end
end
