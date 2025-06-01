require "test_helper"

class MetricsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @auth_headers = { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "password!1") }

    # Clean up existing test data
    HourlyStat.destroy_all
    ErrorRequest.destroy_all

    # Create test data for HourlyStat
    @current_time = Time.current.beginning_of_hour

    # Create hourly stats for the last 48 hours (to test the 24 hour window)
    48.times do |i|
      hour = @current_time - i.hours
      HourlyStat.create!(
        hour: hour,
        total_requests_count: 100 + i,
        error_4xx_count: 5 + i,
        error_5xx_count: 2 + i,
        events_count: 50 + i,
        unique_people_count: 20 + i,
        new_people_count: 10 + i
      )
    end

    # Create test error requests
    10.times do |i|
      ErrorRequest.create!(
        status_code: 400 + (i % 5), # Mix of 400, 401, 402, 403, 404
        request_method: "GET",
        path: "/test/path/#{i}",
        timestamp: @current_time - i.hours,
        ip_address: "127.0.0.1",
        user_agent: "Test Agent"
      )
    end

    # Create some older error requests (outside 24 hour window)
    5.times do |i|
      ErrorRequest.create!(
        status_code: 500,
        request_method: "POST",
        path: "/old/path/#{i}",
        timestamp: @current_time - (25 + i).hours,
        ip_address: "127.0.0.1",
        user_agent: "Test Agent"
      )
    end
  end

  test "should get index without errors" do
    get metrics_url, headers: @auth_headers
    assert_response :success
  end

  test "should assign all required instance variables" do
    get metrics_url, headers: @auth_headers
    assert_response :success

    # Check that all instance variables are assigned
    assert_not_nil assigns(:hourly_stats)
    assert_not_nil assigns(:recent_errors)
    assert_not_nil assigns(:total_requests_24h)
    assert_not_nil assigns(:total_errors_24h)
    assert_not_nil assigns(:error_rate_24h)
    assert_not_nil assigns(:common_error_codes)
  end

  test "should correctly calculate 24h statistics" do
    get metrics_url, headers: @auth_headers
    assert_response :success

    # Should return correct number of hourly stats (but not necessarily 24 since we're using .last())
    hourly_stats = assigns(:hourly_stats)
    assert_kind_of Array, hourly_stats

    # Should have numeric values for totals
    total_requests = assigns(:total_requests_24h)
    total_errors = assigns(:total_errors_24h)
    error_rate = assigns(:error_rate_24h)

    assert_kind_of Numeric, total_requests
    assert_kind_of Numeric, total_errors
    assert_kind_of Numeric, error_rate

    # Error rate should be between 0 and 100
    assert_operator error_rate, :>=, 0
    assert_operator error_rate, :<=, 100
  end

  test "should handle empty hourly stats gracefully" do
    HourlyStat.destroy_all

    get metrics_url, headers: @auth_headers
    assert_response :success

    assert_equal 0, assigns(:total_requests_24h)
    assert_equal 0, assigns(:total_errors_24h)
    assert_equal 0, assigns(:error_rate_24h)
  end

  test "should correctly filter error codes for last 24 hours" do
    get metrics_url, headers: @auth_headers
    assert_response :success

    common_error_codes = assigns(:common_error_codes)
    assert_kind_of Hash, common_error_codes

    # Should only include error codes from last 24 hours
    # Our test data has 10 errors in last 24 hours and 5 older ones
    # The older ones have status_code 500, so 500 should not be in the results
    # if the filtering is working correctly
    recent_error_count = common_error_codes.values.sum
    assert_operator recent_error_count, :<=, 10, "Should only count recent errors"
  end

  test "should limit recent errors to 20" do
    # Create 25 error requests
    25.times do |i|
      ErrorRequest.create!(
        status_code: 400,
        request_method: "GET",
        path: "/extra/path/#{i}",
        timestamp: @current_time - i.minutes,
        ip_address: "127.0.0.1",
        user_agent: "Test Agent"
      )
    end

    get metrics_url, headers: @auth_headers
    assert_response :success

    recent_errors = assigns(:recent_errors)
    assert_operator recent_errors.count, :<=, 20, "Should limit recent errors to 20"
  end

  test "should order error codes by count descending" do
    # Create errors with known distribution
    ErrorRequest.destroy_all

    # Create 5 instances of 404
    5.times do
      ErrorRequest.create!(
        status_code: 404,
        request_method: "GET",
        path: "/not/found",
        timestamp: @current_time - 1.hour,
        ip_address: "127.0.0.1",
        user_agent: "Test Agent"
      )
    end

    # Create 3 instances of 500
    3.times do
      ErrorRequest.create!(
        status_code: 500,
        request_method: "GET",
        path: "/server/error",
        timestamp: @current_time - 1.hour,
        ip_address: "127.0.0.1",
        user_agent: "Test Agent"
      )
    end

    # Create 1 instance of 403
    ErrorRequest.create!(
      status_code: 403,
      request_method: "GET",
      path: "/forbidden",
      timestamp: @current_time - 1.hour,
      ip_address: "127.0.0.1",
      user_agent: "Test Agent"
    )

    get metrics_url, headers: @auth_headers
    assert_response :success

    common_error_codes = assigns(:common_error_codes)

    # Convert to array of [status_code, count] pairs to check ordering
    error_codes_array = common_error_codes.to_a

    # Should be ordered by count descending
    assert_equal 404, error_codes_array.first[0], "404 should be first (highest count)"
    assert_equal 5, error_codes_array.first[1], "404 should have count of 5"

    if error_codes_array.length > 1
      assert_equal 500, error_codes_array.second[0], "500 should be second"
      assert_equal 3, error_codes_array.second[1], "500 should have count of 3"
    end
  end
end
