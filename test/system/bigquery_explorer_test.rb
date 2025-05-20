require "application_system_test_case"

class BigqueryExplorerTest < ApplicationSystemTestCase
  setup do
    # Mock BigqueryService and stubs
    @mock_service = mock("bigquery_service")
    @mock_table = mock("table")
    @mock_schema = mock("schema")
    @mock_data = mock("data")
    @mock_result = mock("result")

    # Setup stubbing for BigqueryService.new
    BigqueryService.stubs(:new).returns(@mock_service)

    # Setup fake tables
    @mock_tables = [
      OpenStruct.new(
        table_id: "web_events",
        description: "Web analytics events",
        created_at: Time.current - 5.days,
        modified_at: Time.current - 1.day,
        project_id: "test-project",
        dataset_id: "test_dataset",
        rows_count: 1000,
        bytes_count: 102400
      ),
      OpenStruct.new(
        table_id: "web_persons",
        description: "Web visitors data",
        created_at: Time.current - 5.days,
        modified_at: Time.current - 1.day,
        project_id: "test-project",
        dataset_id: "test_dataset",
        rows_count: 500,
        bytes_count: 51200
      )
    ]

    # Setup schema
    @mock_fields = [
      OpenStruct.new(name: "id", type: "STRING", mode: "REQUIRED", description: "Unique ID"),
      OpenStruct.new(name: "timestamp", type: "TIMESTAMP", mode: "REQUIRED", description: "Event time"),
      OpenStruct.new(name: "data", type: "RECORD", mode: "NULLABLE", description: "Event data",
        fields: [
          OpenStruct.new(name: "type", type: "STRING", mode: "NULLABLE", description: "Type of data")
        ]
      )
    ]
    @mock_schema = OpenStruct.new(fields: @mock_fields)

    # Setup query result
    @result_fields = [
      OpenStruct.new(name: "id"),
      OpenStruct.new(name: "timestamp")
    ]
    @mock_data = OpenStruct.new(
      fields: @result_fields,
      count: 2,
      entries: [
        {"id" => "id1", "timestamp" => Time.current - 1.day},
        {"id" => "id2", "timestamp" => Time.current - 2.days}
      ],
      each: []
    )

    # Create a method for each that yields entries
    def @mock_data.each
      entries.each { |entry| yield entry }
    end

    # Clone the mock_data for results
    @mock_result = @mock_data.clone

    # Set required ENV variables
    @original_dataset = ENV["BIGQUERY_DATASET"]
    ENV["BIGQUERY_DATASET"] = "test_dataset"

    # Default stubs
    @mock_service.stubs(:tables).returns(@mock_tables)
    @mock_service.stubs(:table).returns(@mock_tables[0])
    @mock_service.stubs(:table_sample_data).returns(@mock_data)
    @mock_service.stubs(:execute_query).returns(@mock_result)
  end

  teardown do
    # Restore ENV variables
    ENV["BIGQUERY_DATASET"] = @original_dataset
  end

  test "visiting the explorer index" do
    @mock_service.expects(:tables).returns(@mock_tables)

    visit bigquery_explorer_url
    assert_selector "h2", text: "BigQuery Explorer"
    assert_selector "h4", text: "Dataset: test_dataset"

    # Check that tables are displayed
    assert_selector ".list-group-item", count: 2
    assert_text "web_events"
    assert_text "web_persons"
  end

  test "viewing table schema" do
    table_id = "web_events"
    @mock_service.expects(:table).with(table_id).returns(@mock_tables[0])
    @mock_tables[0].stubs(:schema).returns(@mock_schema)

    visit table_schema_bigquery_explorer_url(table_id: table_id)

    assert_selector "h2", text: "web_events Schema"
    assert_selector "table tbody tr", minimum: 3  # At least our 3 fields

    # Check field information
    assert_text "id"
    assert_text "STRING"
    assert_text "REQUIRED"

    # Check nested field
    assert_text "data.type"
  end

  test "viewing table data" do
    table_id = "web_events"
    @mock_service.expects(:table).with(table_id).returns(@mock_tables[0])
    @mock_service.expects(:table_sample_data).with(table_id).returns(@mock_data)

    visit table_data_bigquery_explorer_url(table_id: table_id)

    assert_selector "h2", text: "web_events Sample Data"
    assert_selector "table thead th", count: 2  # Our 2 columns
    assert_selector "table tbody tr", count: 2  # Our 2 rows

    # Check for specific data values
    assert_text "id1"
    assert_text "id2"
  end

  test "running a custom query" do
    query = "SELECT * FROM `test_dataset.web_events` LIMIT 10"
    @mock_service.expects(:execute_query).with(query).returns(@mock_result)

    visit query_bigquery_explorer_url

    # Fill directly into the textarea rather than trying to interact with CodeMirror
    # since CodeMirror creates a complex DOM structure
    fill_in "query", with: query
    click_on "Run Query"

    assert_selector "h4", text: "Results"
    assert_selector "table thead th", count: 2  # Our 2 columns
    assert_selector "table tbody tr", count: 2  # Our 2 rows

    # Check for specific data values
    assert_text "id1"
    assert_text "id2"
  end

  test "handling query error" do
    query = "INVALID SQL QUERY"
    @mock_service.expects(:execute_query).with(query).raises(StandardError.new("SQL syntax error"))

    visit query_bigquery_explorer_url

    # Fill directly into the textarea rather than trying to interact with CodeMirror
    fill_in "query", with: query
    click_on "Run Query"

    assert_selector ".alert-danger"
    assert_text "SQL syntax error"
  end
end
