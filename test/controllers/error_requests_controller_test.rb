require "test_helper"

class ErrorRequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @error_request = error_requests(:one)
    @auth_headers = { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "password!1") }
  end

  test "should get index" do
    get error_requests_url, headers: @auth_headers
    assert_response :success
  end

  test "should filter by status code" do
    get error_requests_url, params: { status_code: "404" }, headers: @auth_headers
    assert_response :success
    assert_includes assigns(:error_requests), error_requests(:one)
    assert_not_includes assigns(:error_requests), error_requests(:two)
  end

  test "should filter by request method" do
    get error_requests_url, params: { method: "GET" }, headers: @auth_headers
    assert_response :success
    assert_includes assigns(:error_requests), error_requests(:one)
    assert_not_includes assigns(:error_requests), error_requests(:two)
  end

  test "should filter by path" do
    get error_requests_url, params: { path: "not" }, headers: @auth_headers
    assert_response :success
    assert_includes assigns(:error_requests), error_requests(:one)
    assert_not_includes assigns(:error_requests), error_requests(:two)
  end

  test "should filter by date range" do
    get error_requests_url, params: {
      start_date: 3.hours.ago.to_date.to_s,
      end_date: 1.hour.ago.to_date.to_s
    }, headers: @auth_headers
    assert_response :success
  end

  test "should handle invalid date formats gracefully" do
    get error_requests_url, params: {
      start_date: "invalid-date",
      end_date: "another-invalid-date"
    }, headers: @auth_headers
    assert_response :success
  end

  test "should limit results to 100" do
    # Create more than 100 error requests
    120.times do |i|
      ErrorRequest.create!(
        status_code: 404,
        request_method: "GET",
        path: "/test/#{i}",
        timestamp: Time.current - i.minutes,
        ip_address: "127.0.0.1"
      )
    end

    get error_requests_url, headers: @auth_headers
    assert_response :success
    assert_operator assigns(:error_requests).count, :<=, 100
  end

  test "should show error request" do
    get error_request_url(@error_request), headers: @auth_headers
    assert_response :success
  end

  test "should destroy all error requests" do
    assert_difference("ErrorRequest.count", -ErrorRequest.count) do
      delete destroy_all_error_requests_url, headers: @auth_headers
    end

    assert_redirected_to error_requests_path
  end

  test "should calculate statistics correctly" do
    get error_requests_url, headers: @auth_headers
    assert_response :success

    # Check that statistics are calculated
    assert_not_nil assigns(:total_errors)
    assert_not_nil assigns(:status_code_breakdown)
    assert_not_nil assigns(:method_breakdown)
    assert_not_nil assigns(:path_breakdown)
  end

  test "should handle empty results gracefully" do
    ErrorRequest.destroy_all

    get error_requests_url, headers: @auth_headers
    assert_response :success
    assert_equal 0, assigns(:total_errors)
    assert_equal({}, assigns(:status_code_breakdown))
    assert_equal({}, assigns(:method_breakdown))
    assert_equal({}, assigns(:path_breakdown))
  end

  test "should handle date range with same start and end date" do
    today = Date.current
    get error_requests_url, params: {
      start_date: today.to_s,
      end_date: today.to_s
    }, headers: @auth_headers
    assert_response :success
  end

  test "should handle date range where start date is after end date" do
    get error_requests_url, params: {
      start_date: Date.current.to_s,
      end_date: 1.day.ago.to_date.to_s
    }, headers: @auth_headers
    assert_response :success
  end

  test "should handle partial date parameters" do
    get error_requests_url, params: { start_date: Date.current.to_s }, headers: @auth_headers
    assert_response :success

    get error_requests_url, params: { end_date: Date.current.to_s }, headers: @auth_headers
    assert_response :success
  end
end
