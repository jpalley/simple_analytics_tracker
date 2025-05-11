require "test_helper"
require_relative "../../app/jobs/hubspot_bigquery_sync_job"
require_relative "../../app/models/hubspot_sync_status"
require_relative "../../app/models/error_log"

class HubspotBigquerySyncJobTest < ActiveJob::TestCase
  setup do
    @original_access_token = ENV["HUBSPOT_ACCESS_TOKEN"]
    ENV["HUBSPOT_ACCESS_TOKEN"] = "test_token"
    ENV["GOOGLE_CLOUD_PROJECT"] = "test-project"
    ENV["BIGQUERY_DATASET"] = "test_dataset"

    # Mock BigQuery client
    @mock_bigquery = mock("bigquery")
    @mock_dataset = mock("dataset")
    @mock_table = mock("table")
    @mock_schema = mock("schema")
    @mock_load_job = mock("load_job")

    @mock_bigquery.stubs(:dataset).returns(@mock_dataset)
    @mock_dataset.stubs(:table).returns(@mock_table)
    @mock_table.stubs(:load_job).returns(@mock_load_job)
    @mock_load_job.stubs(:wait_until_done!).returns(true)
    @mock_load_job.stubs(:failed?).returns(false)
    @mock_table.stubs(:schema).yields(@mock_schema).returns(@mock_schema)
    @mock_schema.stubs(:string).returns(true)
    @mock_schema.stubs(:timestamp).returns(true)

    Google::Cloud::Bigquery.stubs(:new).returns(@mock_bigquery)

    # Mock Hubspot client
    @mock_hubspot = mock("hubspot_client")
    HubspotClient.stubs(:new).returns(@mock_hubspot)

    # Setup mock responses for Hubspot client
    mock_contacts_response = OpenStruct.new(
      results: [ { "id" => "1", "properties" => { "firstname" => "Test", "lastname" => "User" } } ],
      paging: OpenStruct.new(next: OpenStruct.new(after: "offset123"))
    )

    mock_companies_response = OpenStruct.new(
      results: [ { "id" => "1", "properties" => { "name" => "Test Company" } } ],
      paging: nil
    )

    @mock_hubspot.stubs(:get_contacts).returns(mock_contacts_response)
    @mock_hubspot.stubs(:get_companies).returns(mock_companies_response)

    # Mock log_error method
    HubspotBigquerySyncJob.any_instance.stubs(:log_error).returns(true)
  end

  teardown do
    ENV["HUBSPOT_ACCESS_TOKEN"] = @original_access_token
  end

  test "should raise error if HUBSPOT_ACCESS_TOKEN is not set" do
    ENV["HUBSPOT_ACCESS_TOKEN"] = nil

    error = assert_raises(RuntimeError) do
      HubspotBigquerySyncJob.perform_now
    end

    assert_match(/HUBSPOT_ACCESS_TOKEN is not configured/, error.message)
  end

  test "should create error log when exception is raised" do
    HubspotBigquerySyncJob.any_instance.stubs(:sync_object).with(:contacts, full_sync: false).raises(StandardError, "Test error")

    HubspotBigquerySyncJob.any_instance.expects(:log_error).with(
      "Hubspot BigQuery Sync Error - contacts",
      includes("Test error")
    ).returns(true)

    assert_raises(StandardError) do
      HubspotBigquerySyncJob.perform_now("contacts")
    end
  end

  test "should update hubspot sync status on success" do
    # Skip actual API calls and BigQuery operations
    HubspotBigquerySyncJob.any_instance.stubs(:sync_object).returns(true)

    # Expect the status to be updated
    HubspotSyncStatus.expects(:create_or_update).with(
      has_entries(
        object_type: "all",
        status: "success",
        synced_at: instance_of(ActiveSupport::TimeWithZone)
      )
    )

    HubspotBigquerySyncJob.perform_now
  end

  test "should update hubspot sync status on error" do
    HubspotBigquerySyncJob.any_instance.stubs(:sync_object).raises(StandardError, "Test error")

    # Expect the error status to be updated
    HubspotSyncStatus.expects(:create_or_update).with(
      has_entries(
        object_type: "contacts",
        status: "error",
        error_message: includes("Test error")
      )
    )

    assert_raises(StandardError) do
      HubspotBigquerySyncJob.perform_now("contacts")
    end
  end

  test "should respect full_sync parameter" do
    # Test that full_sync is passed to sync_object
    HubspotBigquerySyncJob.any_instance.expects(:sync_object).with(:contacts, full_sync: true).returns(true)

    HubspotBigquerySyncJob.perform_now("contacts", full_sync: true)
  end

  test "should handle pagination properly for contacts" do
    mock_first_response = OpenStruct.new(
      results: [ { "id" => "1", "properties" => { "firstname" => "Test", "lastname" => "User" } } ],
      paging: OpenStruct.new(next: OpenStruct.new(after: "offset123"))
    )

    mock_second_response = OpenStruct.new(
      results: [ { "id" => "2", "properties" => { "firstname" => "Test2", "lastname" => "User2" } } ],
      paging: nil
    )

    # Stub the get_contacts method to return different responses on consecutive calls
    @mock_hubspot.expects(:get_contacts).with(limit: 100, after: nil).returns(mock_first_response)
    @mock_hubspot.expects(:get_contacts).with(limit: 100, after: "offset123").returns(mock_second_response)

    # Stub other methods to focus on pagination
    HubspotBigquerySyncJob.any_instance.stubs(:initialize_bigquery_client).returns(@mock_bigquery)
    HubspotBigquerySyncJob.any_instance.stubs(:initialize_bigquery_dataset).returns(@mock_dataset)
    HubspotBigquerySyncJob.any_instance.stubs(:sync_records_to_bigquery).returns(true)

    # Run the job for contacts only
    HubspotBigquerySyncJob.perform_now("contacts")
  end

  test "should use incremental sync when full_sync is false and last sync exists" do
    # Create a mock last sync time
    last_sync_time = Time.current - 1.day

    # Mock the get_last_sync_time method to return our test time
    HubspotBigquerySyncJob.any_instance.stubs(:get_last_sync_time).with(:contacts).returns(last_sync_time.iso8601)

    # Expect get_contacts to be called with the updated_after parameter
    @mock_hubspot.expects(:get_contacts).with(
      has_entries(
        limit: 100,
        after: nil,
        updated_after: last_sync_time.iso8601
      )
    ).returns(OpenStruct.new(results: [], paging: nil))

    # Stub other methods to focus on the incremental sync parameter
    HubspotBigquerySyncJob.any_instance.stubs(:initialize_bigquery_client).returns(@mock_bigquery)
    HubspotBigquerySyncJob.any_instance.stubs(:initialize_bigquery_dataset).returns(@mock_dataset)

    # Run the job with incremental sync
    HubspotBigquerySyncJob.perform_now("contacts", full_sync: false)
  end

  test "should expand properties from nested hash" do
    record = {
      "id" => "1",
      "properties" => {
        "firstname" => "Test",
        "lastname" => "User",
        "email" => "test@example.com"
      }
    }

    expanded = HubspotBigquerySyncJob.new.send(:expand_properties, record, :contacts)

    assert_equal "Test", expanded["firstname"]
    assert_equal "User", expanded["lastname"]
    assert_equal "test@example.com", expanded["email"]
    assert_equal record["properties"], expanded["all_properties"]
  end
end
