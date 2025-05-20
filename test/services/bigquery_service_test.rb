require "test_helper"
require "google/cloud/bigquery"

class BigqueryServiceTest < ActiveSupport::TestCase
  setup do
    # Mock environment variables
    @original_project = ENV["GOOGLE_CLOUD_PROJECT"]
    @original_dataset = ENV["BIGQUERY_DATASET"]
    @original_credentials = ENV["GOOGLE_CLOUD_CREDENTIALS"]

    ENV["GOOGLE_CLOUD_PROJECT"] = "test-project"
    ENV["BIGQUERY_DATASET"] = "test_dataset"
    ENV["GOOGLE_CLOUD_CREDENTIALS"] = '{"test": "credentials"}'

    # Mock BigQuery client and related objects
    @mock_bigquery = mock("bigquery")
    @mock_dataset = mock("dataset")
    @mock_table = mock("table")
    @mock_schema = mock("schema")
    @mock_field = mock("field")

    # Stub the Google::Cloud::Bigquery.new method to return our mock
    Google::Cloud::Bigquery.stubs(:new).returns(@mock_bigquery)

    # Setup basic stubs for common methods
    @mock_bigquery.stubs(:dataset).returns(@mock_dataset)
    @mock_dataset.stubs(:table).returns(@mock_table)
  end

  teardown do
    # Restore environment variables
    ENV["GOOGLE_CLOUD_PROJECT"] = @original_project
    ENV["BIGQUERY_DATASET"] = @original_dataset
    ENV["GOOGLE_CLOUD_CREDENTIALS"] = @original_credentials
  end

  test "initialize creates a BigQuery client" do
    Google::Cloud::Bigquery.expects(:new).with(
      project: "test-project",
      credentials: {"test" => "credentials"}
    ).returns(@mock_bigquery)

    service = BigqueryService.new
    assert_not_nil service
  end

  test "dataset returns the correct dataset" do
    @mock_bigquery.expects(:dataset).with("test_dataset").returns(@mock_dataset)

    service = BigqueryService.new
    assert_equal @mock_dataset, service.dataset
  end

  test "tables returns list of tables from the dataset" do
    mock_tables = [mock("table1"), mock("table2")]
    @mock_dataset.expects(:tables).returns(mock_tables)

    service = BigqueryService.new
    assert_equal mock_tables, service.tables
  end

  test "table returns a specific table" do
    @mock_dataset.expects(:table).with("test_table").returns(@mock_table)

    service = BigqueryService.new
    assert_equal @mock_table, service.table("test_table")
  end

  test "execute_query runs the query and returns results" do
    query = "SELECT * FROM test_table"
    mock_results = mock("results")
    @mock_bigquery.expects(:query).with(query).returns(mock_results)

    service = BigqueryService.new
    assert_equal mock_results, service.execute_query(query)
  end

  test "table_sample_data gets sample data from a table" do
    table_id = "test_table"
    expected_query = "SELECT * FROM `test_dataset.test_table` LIMIT 10"
    mock_results = mock("results")

    @mock_bigquery.expects(:query).with(expected_query).returns(mock_results)

    service = BigqueryService.new
    assert_equal mock_results, service.table_sample_data(table_id)
  end

  test "table_row_count gets count of rows in a table" do
    table_id = "test_table"
    expected_query = "SELECT COUNT(*) as count FROM `test_dataset.test_table`"
    mock_results = [{"count" => 42}]

    @mock_bigquery.expects(:query).with(expected_query).returns(mock_results)

    service = BigqueryService.new
    assert_equal 42, service.table_row_count(table_id)
  end

  test "table_row_count returns nil on error" do
    table_id = "test_table"

    @mock_bigquery.expects(:query).raises(BigqueryService::BigQueryError.new("Test error"))

    service = BigqueryService.new
    assert_nil service.table_row_count(table_id)
  end
end
