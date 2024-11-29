require "test_helper"

class ErrorLogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @error_log = error_logs(:one)
  end

  test "should get index" do
    get error_logs_url
    assert_response :success
  end

  test "should get new" do
    get new_error_log_url
    assert_response :success
  end

  test "should create error_log" do
    assert_difference("ErrorLog.count") do
      post error_logs_url, params: { error_log: { body: @error_log.body, title: @error_log.title } }
    end

    assert_redirected_to error_log_url(ErrorLog.last)
  end

  test "should show error_log" do
    get error_log_url(@error_log)
    assert_response :success
  end

  test "should get edit" do
    get edit_error_log_url(@error_log)
    assert_response :success
  end

  test "should update error_log" do
    patch error_log_url(@error_log), params: { error_log: { body: @error_log.body, title: @error_log.title } }
    assert_redirected_to error_log_url(@error_log)
  end

  test "should destroy error_log" do
    assert_difference("ErrorLog.count", -1) do
      delete error_log_url(@error_log)
    end

    assert_redirected_to error_logs_url
  end
end
