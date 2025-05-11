require "test_helper"
require_relative "../../app/jobs/hubspot_bigquery_sync_job"
require_relative "../../app/models/hubspot_sync_status"

class HubspotControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Set basic auth credentials for AdminController
    @auth_headers = { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "password!1") }

    # Mock HubspotSyncStatus to avoid database operations
    @mock_status = mock("hubspot_sync_status")
    @mock_status.stubs(:synced_at).returns(Time.current)
    @mock_status.stubs(:record_count).returns(100)
    @mock_status.stubs(:status).returns("success")

    HubspotSyncStatus.stubs(:order).returns(HubspotSyncStatus)
    HubspotSyncStatus.stubs(:limit).returns([])
    HubspotSyncStatus.stubs(:find_or_initialize_by).returns(@mock_status)
    HubspotSyncStatus.stubs(:create_or_update).returns(@mock_status)
    HubspotSyncStatus.stubs(:last_successful_sync).returns(@mock_status)
    HubspotSyncStatus.stubs(:last_sync).returns(@mock_status)
  end

  test "should get index" do
    get hubspot_index_url, headers: @auth_headers
    assert_response :success

    # Use assert_template from rails-controller-testing
    assert_template :index

    # Check that all required instance variables are assigned
    assert_not_nil assigns(:sync_statuses)
    assert_not_nil assigns(:object_types)
    assert_not_nil assigns(:last_syncs)
  end

  test "should queue sync job for specific object" do
    HubspotSyncStatus.expects(:create_or_update).with(
      object_type: "contacts",
      status: "in_progress"
    ).returns(@mock_status)

    assert_enqueued_with(job: HubspotBigquerySyncJob, args: [ "contacts", { full_sync: false } ]) do
      post sync_hubspot_index_url, params: { object_type: "contacts" }, headers: @auth_headers
    end

    assert_redirected_to hubspot_index_url
    assert_equal "Incremental sync job for contacts has been queued", flash[:notice]
  end

  test "should queue full sync job for specific object" do
    HubspotSyncStatus.expects(:create_or_update).with(
      object_type: "contacts",
      status: "in_progress"
    ).returns(@mock_status)

    assert_enqueued_with(job: HubspotBigquerySyncJob, args: [ "contacts", { full_sync: true } ]) do
      post sync_hubspot_index_url, params: { object_type: "contacts", full_sync: "true" }, headers: @auth_headers
    end

    assert_redirected_to hubspot_index_url
    assert_equal "Full sync job for contacts has been queued", flash[:notice]
  end

  test "should queue sync job for all objects" do
    HubspotBigquerySyncJob::HUBSPOT_OBJECTS.keys.each do |type|
      HubspotSyncStatus.expects(:create_or_update).with(
        object_type: type.to_s,
        status: "in_progress"
      ).returns(@mock_status)
    end

    assert_enqueued_with(job: HubspotBigquerySyncJob, args: [ nil, { full_sync: false } ]) do
      post sync_hubspot_index_url, headers: @auth_headers
    end

    assert_redirected_to hubspot_index_url
    assert_equal "Incremental sync job for all Hubspot objects has been queued", flash[:notice]
  end
end
