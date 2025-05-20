class BigqueryExplorerController < ApplicationController
  before_action :initialize_bigquery_service

  def index
    @dataset_id = ENV["BIGQUERY_DATASET"]
    @tables = @bigquery_service.tables
  rescue => e
    flash.now[:alert] = "Error connecting to BigQuery: #{e.message}"
    @tables = []
  end

  def table_schema
    @dataset_id = ENV["BIGQUERY_DATASET"]
    @table = @bigquery_service.table(params[:table_id])
    @schema = @table.schema
  rescue => e
    flash[:alert] = "Error fetching table schema: #{e.message}"
    redirect_to bigquery_explorer_path
  end

  def table_data
    @dataset_id = ENV["BIGQUERY_DATASET"]
    @table = @bigquery_service.table(params[:table_id])

    # Get sample data (up to 10 rows)
    @data = @bigquery_service.table_sample_data(params[:table_id])
  rescue => e
    flash[:alert] = "Error fetching table data: #{e.message}"
    redirect_to bigquery_explorer_path
  end

  def query
    @query = params[:query]

    if @query.present?
      begin
        @result = @bigquery_service.execute_query(@query)
        @error = nil
      rescue => e
        @error = "Error executing query: #{e.message}"
        @result = nil
      end
    end
  end

  private

  def initialize_bigquery_service
    @bigquery_service = BigqueryService.new
  rescue => e
    flash.now[:alert] = "Failed to initialize BigQuery service: #{e.message}"
  end
end
