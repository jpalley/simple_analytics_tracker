require "test_helper"

class FacebookSyncsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @facebook_sync = facebook_syncs(:one)
  end

  test "should get index" do
    get facebook_syncs_url
    assert_response :success
  end

  test "should get new" do
    get new_facebook_sync_url
    assert_response :success
  end

  test "should create facebook_sync" do
    assert_difference("FacebookSync.count") do
      post facebook_syncs_url, params: { facebook_sync: { event_name: @facebook_sync.event_name, event_value: @facebook_sync.event_value, last_counter: @facebook_sync.last_counter, table_name: @facebook_sync.table_name } }
    end

    assert_redirected_to facebook_sync_url(FacebookSync.last)
  end

  test "should show facebook_sync" do
    get facebook_sync_url(@facebook_sync)
    assert_response :success
  end

  test "should get edit" do
    get edit_facebook_sync_url(@facebook_sync)
    assert_response :success
  end

  test "should update facebook_sync" do
    patch facebook_sync_url(@facebook_sync), params: { facebook_sync: { event_name: @facebook_sync.event_name, event_value: @facebook_sync.event_value, last_counter: @facebook_sync.last_counter, table_name: @facebook_sync.table_name } }
    assert_redirected_to facebook_sync_url(@facebook_sync)
  end

  test "should destroy facebook_sync" do
    assert_difference("FacebookSync.count", -1) do
      delete facebook_sync_url(@facebook_sync)
    end

    assert_redirected_to facebook_syncs_url
  end
end
