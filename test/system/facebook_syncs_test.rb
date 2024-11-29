require "application_system_test_case"

class FacebookSyncsTest < ApplicationSystemTestCase
  setup do
    @facebook_sync = facebook_syncs(:one)
  end

  test "visiting the index" do
    visit facebook_syncs_url
    assert_selector "h1", text: "Facebook syncs"
  end

  test "should create facebook sync" do
    visit facebook_syncs_url
    click_on "New facebook sync"

    fill_in "Event name", with: @facebook_sync.event_name
    fill_in "Event value", with: @facebook_sync.event_value
    fill_in "Last counter", with: @facebook_sync.last_counter
    fill_in "Table name", with: @facebook_sync.table_name
    click_on "Create Facebook sync"

    assert_text "Facebook sync was successfully created"
    click_on "Back"
  end

  test "should update Facebook sync" do
    visit facebook_sync_url(@facebook_sync)
    click_on "Edit this facebook sync", match: :first

    fill_in "Event name", with: @facebook_sync.event_name
    fill_in "Event value", with: @facebook_sync.event_value
    fill_in "Last counter", with: @facebook_sync.last_counter
    fill_in "Table name", with: @facebook_sync.table_name
    click_on "Update Facebook sync"

    assert_text "Facebook sync was successfully updated"
    click_on "Back"
  end

  test "should destroy Facebook sync" do
    visit facebook_sync_url(@facebook_sync)
    click_on "Destroy this facebook sync", match: :first

    assert_text "Facebook sync was successfully destroyed"
  end
end
