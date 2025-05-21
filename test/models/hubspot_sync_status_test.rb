require "test_helper"

class HubspotSyncStatusTest < ActiveSupport::TestCase
  test "create_or_update creates new record for in_progress status" do
    before_count = HubspotSyncStatus.count

    status = HubspotSyncStatus.create_or_update(
      object_type: "contacts",
      status: "in_progress"
    )

    assert_equal before_count + 1, HubspotSyncStatus.count
    assert status.persisted?
    assert_equal "contacts", status.object_type
    assert_equal "in_progress", status.status
  end

  test "create_or_update updates existing record for success status" do
    # First create an in-progress status
    in_progress = HubspotSyncStatus.create_or_update(
      object_type: "contacts",
      status: "in_progress"
    )

    before_count = HubspotSyncStatus.count

    # Now update it to success
    success = HubspotSyncStatus.create_or_update(
      object_type: "contacts",
      status: "success",
      record_count: 42,
      synced_at: Time.current
    )

    # Should update same record, not create a new one
    assert_equal before_count, HubspotSyncStatus.count
    assert_equal in_progress.id, success.id
    assert_equal "success", success.status
    assert_equal 42, success.record_count
  end

  test "create_or_update updates existing record for error status" do
    # First create an in-progress status
    in_progress = HubspotSyncStatus.create_or_update(
      object_type: "companies",
      status: "in_progress"
    )

    before_count = HubspotSyncStatus.count

    # Now update it to error
    error = HubspotSyncStatus.create_or_update(
      object_type: "companies",
      status: "error",
      error_message: "Something went wrong"
    )

    # Should update same record, not create a new one
    assert_equal before_count, HubspotSyncStatus.count
    assert_equal in_progress.id, error.id
    assert_equal "error", error.status
    assert_equal "Something went wrong", error.error_message
  end

  test "create_or_update creates new record if no in_progress record exists" do
    # Make sure there are no in-progress records
    HubspotSyncStatus.in_progress.destroy_all

    before_count = HubspotSyncStatus.count

    # Create a success status without a preceding in-progress
    status = HubspotSyncStatus.create_or_update(
      object_type: "deals",
      status: "success",
      record_count: 10,
      synced_at: Time.current
    )

    # Should create a new record
    assert_equal before_count + 1, HubspotSyncStatus.count
    assert status.persisted?
    assert_equal "deals", status.object_type
    assert_equal "success", status.status
  end

  test "last_successful_sync returns most recent successful sync by synced_at" do
    # Create old sync
    old_sync = HubspotSyncStatus.create!(
      object_type: "contacts",
      status: "success",
      synced_at: 2.days.ago
    )

    # Create newer sync
    new_sync = HubspotSyncStatus.create!(
      object_type: "contacts",
      status: "success",
      synced_at: 1.day.ago
    )

    # Create sync for different object
    other_sync = HubspotSyncStatus.create!(
      object_type: "companies",
      status: "success",
      synced_at: Time.current
    )

    # Should return the newer one for contacts
    assert_equal new_sync, HubspotSyncStatus.last_successful_sync("contacts")

    # Should return the other one for companies
    assert_equal other_sync, HubspotSyncStatus.last_successful_sync("companies")
  end
end
