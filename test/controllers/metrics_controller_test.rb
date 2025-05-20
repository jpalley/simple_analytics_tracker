require "test_helper"

class MetricsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @auth_headers = { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "password!1") }
  end

  test "should get index" do
    get metrics_url, headers: @auth_headers
    assert_response :success
  end
end
