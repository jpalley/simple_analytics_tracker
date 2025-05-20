require "test_helper"

class BigqueryExplorerControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Mock BigqueryService and stubs
    @mock_service = mock("bigquery_service")
    @mock_table = mock("table")
    @mock_schema = mock("schema")
    @mock_data = mock("data")
    @mock_result = mock("result")

    # Setup stubbing for BigqueryService.new
    BigqueryService.stubs(:new).returns(@mock_service)

    # Setup default behavior for mocks
    @mock_service.stubs(:tables).returns([])
    @mock_service.stubs(:table).returns(@mock_table)
    @mock_table.stubs(:schema).returns(@mock_schema)
    @mock_service.stubs(:table_sample_data).returns(@mock_data)
    @mock_service.stubs(:execute_query).returns(@mock_result)

    # Add additional stubs for table properties used in views
    @mock_table.stubs(:table_id).returns("test_table")
    @mock_table.stubs(:description).returns("Test table description")
    @mock_table.stubs(:created_at).returns(Time.current)
    @mock_table.stubs(:modified_at).returns(Time.current)
    @mock_table.stubs(:project_id).returns("test-project")
    @mock_table.stubs(:dataset_id).returns("test_dataset")
    @mock_table.stubs(:rows_count).returns(100)
    @mock_table.stubs(:bytes_count).returns(10240)

    # Add stubs for result
    @mock_result.stubs(:count).returns(2)
    @mock_result.stubs(:fields).returns([])
    @mock_result.stubs(:each).returns([])
    @mock_data.stubs(:count).returns(2)
    @mock_data.stubs(:fields).returns([])
    @mock_data.stubs(:each).returns([])

    # Add stubs for schema
    @mock_schema.stubs(:fields).returns([])
    @mock_schema.stubs(:present?).returns(true)

    # Set required ENV variables
    @original_dataset = ENV["BIGQUERY_DATASET"]
    ENV["BIGQUERY_DATASET"] = "test_dataset"
  end

  teardown do
    # Restore ENV variables
    ENV["BIGQUERY_DATASET"] = @original_dataset
  end

  test "should get index" do
    mock_tables = [mock("table1"), mock("table2")]
    mock_tables.each do |table|
      table.stubs(:table_id).returns("test_table")
      table.stubs(:description).returns("Test description")
      table.stubs(:created_at).returns(Time.current)
      table.stubs(:modified_at).returns(Time.current)
    end
    @mock_service.expects(:tables).returns(mock_tables)

    get bigquery_explorer_url
    assert_response :success
    assert_equal mock_tables, assigns(:tables)
  end

  test "should handle error in index" do
    @mock_service.expects(:tables).raises(StandardError.new("Test error"))

    get bigquery_explorer_url
    assert_response :success
    assert_equal [], assigns(:tables)
    assert_match "Test error", flash[:alert]
  end

  test "should get table_schema" do
    table_id = "test_table"
    @mock_service.expects(:table).with(table_id).returns(@mock_table)
    @mock_table.expects(:schema).returns(@mock_schema)

    get table_schema_bigquery_explorer_url, params: { table_id: table_id }
    assert_response :success
    assert_equal @mock_table, assigns(:table)
    assert_equal @mock_schema, assigns(:schema)
  end

  test "should handle error in table_schema" do
    table_id = "test_table"
    @mock_service.expects(:table).with(table_id).raises(StandardError.new("Test error"))

    get table_schema_bigquery_explorer_url, params: { table_id: table_id }
    assert_redirected_to bigquery_explorer_path
    assert_match "Test error", flash[:alert]
  end

  test "should get table_data" do
    table_id = "test_table"
    @mock_service.expects(:table).with(table_id).returns(@mock_table)
    @mock_service.expects(:table_sample_data).with(table_id).returns(@mock_data)

    get table_data_bigquery_explorer_url, params: { table_id: table_id }
    assert_response :success
    assert_equal @mock_table, assigns(:table)
    assert_equal @mock_data, assigns(:data)
  end

  test "should handle error in table_data" do
    table_id = "test_table"
    @mock_service.expects(:table).with(table_id).raises(StandardError.new("Test error"))

    get table_data_bigquery_explorer_url, params: { table_id: table_id }
    assert_redirected_to bigquery_explorer_path
    assert_match "Test error", flash[:alert]
  end

  test "should get query without executing when no query provided" do
    get query_bigquery_explorer_url
    assert_response :success
    assert_nil assigns(:result)
    assert_nil assigns(:error)
  end

  test "should get query with results" do
    query = "SELECT * FROM test_table"
    @mock_service.expects(:execute_query).with(query).returns(@mock_result)

    get query_bigquery_explorer_url, params: { query: query }
    assert_response :success
    assert_equal query, assigns(:query)
    assert_equal @mock_result, assigns(:result)
    assert_nil assigns(:error)
  end

  test "should handle error in query execution" do
    query = "INVALID SQL"
    @mock_service.expects(:execute_query).with(query).raises(StandardError.new("SQL syntax error"))

    get query_bigquery_explorer_url, params: { query: query }
    assert_response :success
    assert_equal query, assigns(:query)
    assert_nil assigns(:result)
    assert_match "SQL syntax error", assigns(:error)
  end
end
