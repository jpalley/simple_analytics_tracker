require "test_helper"

class TrackingControllerTest < ActionDispatch::IntegrationTest
  def setup
    @person_uuid = "test-uuid-123"
    @person = Person.create!(
      uuid: @person_uuid,
      properties: {}
    )
  end

  test "update_email adds email when person exists and email is blank" do
    post "/track/update_email", params: {
      email: "test@example.com",
      SA_UUID: @person_uuid,
      oir_source: "AUTOFILLED_TRACKING_ID"
    }

    assert_response :ok
    response_body = JSON.parse(response.body)
    assert_equal "success", response_body["status"]
    assert_equal "Email added successfully", response_body["message"]

    @person.reload
    assert_equal "test@example.com", @person.properties["email"]
    assert_equal "AUTOFILLED_TRACKING_ID", @person.properties["oir_source"]
  end

  test "update_email does not overwrite existing email" do
    existing_email = "existing@example.com"
    @person.update!(properties: { "email" => existing_email })

    post "/track/update_email", params: {
      email: "new@example.com",
      SA_UUID: @person_uuid,
      oir_source: "AUTOFILLED_TRACKING_ID"
    }

    assert_response :ok
    response_body = JSON.parse(response.body)
    assert_equal "success", response_body["status"]
    assert_equal "Email already exists, not overwritten", response_body["message"]

    @person.reload
    assert_equal existing_email, @person.properties["email"]
  end

  test "update_email returns error when person not found" do
    post "/track/update_email", params: {
      email: "test@example.com",
      SA_UUID: "non-existent-uuid",
      oir_source: "AUTOFILLED_TRACKING_ID"
    }

    assert_response :not_found
    response_body = JSON.parse(response.body)
    assert_equal "error", response_body["status"]
    assert_equal "Person not found", response_body["message"]
  end

  test "update_email works when person has nil properties" do
    @person.update!(properties: nil)

    post "/track/update_email", params: {
      email: "test@example.com",
      SA_UUID: @person_uuid,
      oir_source: "AUTOFILLED_TRACKING_ID"
    }

    assert_response :ok
    response_body = JSON.parse(response.body)
    assert_equal "success", response_body["status"]

    @person.reload
    assert_equal "test@example.com", @person.properties["email"]
    assert_equal "AUTOFILLED_TRACKING_ID", @person.properties["oir_source"]
  end

  test "update_email handles empty string email as blank" do
    @person.update!(properties: { "email" => "" })

    post "/track/update_email", params: {
      email: "test@example.com",
      SA_UUID: @person_uuid,
      oir_source: "AUTOFILLED_TRACKING_ID"
    }

    assert_response :ok
    response_body = JSON.parse(response.body)
    assert_equal "success", response_body["status"]
    assert_equal "Email added successfully", response_body["message"]

    @person.reload
    assert_equal "test@example.com", @person.properties["email"]
  end

  test "update_email handles nil email as blank" do
    @person.update!(properties: { "email" => nil })

    post "/track/update_email", params: {
      email: "test@example.com",
      SA_UUID: @person_uuid,
      oir_source: "AUTOFILLED_TRACKING_ID"
    }

    assert_response :ok
    response_body = JSON.parse(response.body)
    assert_equal "success", response_body["status"]
    assert_equal "Email added successfully", response_body["message"]

    @person.reload
    assert_equal "test@example.com", @person.properties["email"]
  end

  test "update_email requires all parameters" do
    # Test missing email
    post "/track/update_email", params: {
      SA_UUID: @person_uuid,
      oir_source: "AUTOFILLED_TRACKING_ID"
    }

    assert_response :ok  # Should still work with missing email
    response_body = JSON.parse(response.body)
    assert_equal "success", response_body["status"]

    # Test missing SA_UUID
    post "/track/update_email", params: {
      email: "test@example.com",
      oir_source: "AUTOFILLED_TRACKING_ID"
    }

    assert_response :not_found  # Person with nil UUID won't be found
  end

  test "update_email preserves other properties" do
    @person.update!(properties: { "name" => "John Doe", "age" => 30 })

    post "/track/update_email", params: {
      email: "test@example.com",
      SA_UUID: @person_uuid,
      oir_source: "AUTOFILLED_TRACKING_ID"
    }

    assert_response :ok
    @person.reload
    assert_equal "test@example.com", @person.properties["email"]
    assert_equal "AUTOFILLED_TRACKING_ID", @person.properties["oir_source"]
    assert_equal "John Doe", @person.properties["name"]
    assert_equal 30, @person.properties["age"]
  end
end
