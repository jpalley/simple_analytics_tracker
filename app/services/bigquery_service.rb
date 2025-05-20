class BigqueryService
  class BigQueryError < StandardError; end

  def initialize
    @project_id = ENV["GOOGLE_CLOUD_PROJECT"]
    @dataset_id = ENV["BIGQUERY_DATASET"]
    @client = initialize_client
  end

  def dataset
    @dataset ||= begin
      @client.dataset(@dataset_id) || @client.create_dataset(@dataset_id)
    end
  end

  def tables
    dataset.tables
  end

  def table(table_id)
    dataset.table(table_id)
  end

  def execute_query(query)
    @client.query(query)
  rescue Google::Cloud::Error => e
    raise BigQueryError, "Query execution failed: #{e.message}"
  end

  def table_sample_data(table_id, limit = 10)
    query = "SELECT * FROM `#{@dataset_id}.#{table_id}` LIMIT #{limit}"
    execute_query(query)
  end

  def table_row_count(table_id)
    query = "SELECT COUNT(*) as count FROM `#{@dataset_id}.#{table_id}`"
    result = execute_query(query)
    result.first["count"]
  rescue BigQueryError
    nil
  end

  def tables_with_metadata
    tables.map do |table|
      {
        id: table.table_id,
        name: table.table_id.gsub('_', ' ').titleize,
        description: table.description,
        created_at: table.created_at,
        modified_at: table.modified_at,
        schema: table.schema,
        row_count: table_row_count(table.table_id),
        size_bytes: table.num_bytes
      }
    end
  end

  private

  def initialize_client
    if Rails.env.development?
      begin
        # In development, try parsing the credentials directly first
        credentials = JSON.parse(ENV["GOOGLE_CLOUD_CREDENTIALS"])

        Google::Cloud::Bigquery.new(
          project: @project_id,
          credentials: credentials
        )
      rescue JSON::ParserError => e
        # If direct parsing fails, try with the format manipulation
        Google::Cloud::Bigquery.new(
          project: @project_id,
          credentials: JSON.parse(ENV["GOOGLE_CLOUD_CREDENTIALS"].gsub(/(?<!\\)(\\n)/, "").gsub('\n', "n"))
        )
      end
    else
      # Production implementation
      Google::Cloud::Bigquery.new(
        project: @project_id,
        credentials: JSON.parse(ENV["GOOGLE_CLOUD_CREDENTIALS"].gsub(/(?<!\\)(\\n)/, "").gsub('\n', "n"))
      )
    end
  rescue => e
    Rails.logger.error("Failed to initialize BigQuery client: #{e.message}")
    raise BigQueryError, "Failed to initialize BigQuery client: #{e.message}"
  end
end
