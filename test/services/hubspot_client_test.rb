require "test_helper"

class HubspotClientTest < ActiveSupport::TestCase
  setup do
    @original_access_token = ENV["HUBSPOT_ACCESS_TOKEN"]
    ENV["HUBSPOT_ACCESS_TOKEN"] = "test_access_token"

    # Mock the Hubspot API client
    @mock_api_client = mock("hubspot_api_client")
    @mock_contacts_api = mock("contacts_api")
    @mock_search_api = mock("search_api")
    @mock_basic_api = mock("basic_api")
    @mock_crm = mock("crm")

    @mock_api_client.stubs(:crm).returns(@mock_crm)
    @mock_crm.stubs(:contacts).returns(@mock_contacts_api)
    @mock_contacts_api.stubs(:search_api).returns(@mock_search_api)
    @mock_contacts_api.stubs(:basic_api).returns(@mock_basic_api)

    Hubspot::Client.stubs(:new).returns(@mock_api_client)

    @client = HubspotClient.new
  end

  teardown do
    ENV["HUBSPOT_ACCESS_TOKEN"] = @original_access_token
  end

  test "contacts_by_email returns empty hash when no emails provided" do
    result = @client.contacts_by_email([])
    assert_equal({}, result)
  end

  test "contacts_by_email searches and returns contacts by email" do
    emails = [ "test1@example.com", "test2@example.com" ]

    # Mock property definitions
    @client.stubs(:get_all_property_definitions).with(:contacts).returns({
      "email" => { "name" => "email" },
      "firstname" => { "name" => "firstname" }
    })

    # Mock search response
    mock_response = OpenStruct.new(
      results: [
        {
          "id" => "contact1",
          "properties" => { "email" => "test1@example.com", "firstname" => "John" }
        },
        {
          "id" => "contact2",
          "properties" => { "email" => "test2@example.com", "firstname" => "Jane" }
        }
      ]
    )

    expected_search_request = {
      limit: 100,
      properties: [ "email", "firstname" ],
      filterGroups: [
        {
          filters: [
            { propertyName: "email", operator: "EQ", value: "test1@example.com" },
            { propertyName: "email", operator: "EQ", value: "test2@example.com" }
          ]
        }
      ]
    }

    @mock_search_api.expects(:do_search)
                   .with(public_object_search_request: expected_search_request)
                   .returns(mock_response)

    result = @client.contacts_by_email(emails)

    assert_equal 2, result.keys.length
    assert_equal "contact1", result["test1@example.com"]["id"]
    assert_equal "contact2", result["test2@example.com"]["id"]
  end

  test "contacts_by_email handles contacts with to_hash method" do
    emails = [ "test@example.com" ]

    @client.stubs(:get_all_property_definitions).with(:contacts).returns({})

    # Mock contact object that responds to to_hash
    mock_contact = mock("contact")
    mock_contact.stubs(:respond_to?).with(:to_hash).returns(true)
    mock_contact.stubs(:to_hash).returns({
      "id" => "contact123",
      "properties" => { "email" => "test@example.com" }
    })

    mock_response = OpenStruct.new(results: [ mock_contact ])
    @mock_search_api.stubs(:do_search).returns(mock_response)

    result = @client.contacts_by_email(emails)

    assert_equal "contact123", result["test@example.com"]["id"]
  end

  test "contacts_by_email handles empty property definitions gracefully" do
    emails = [ "test@example.com" ]

    @client.stubs(:get_all_property_definitions).with(:contacts).returns({})

    mock_response = OpenStruct.new(
      results: [
        {
          "id" => "contact1",
          "properties" => { "email" => "test@example.com" }
        }
      ]
    )

    expected_search_request = {
      limit: 100,
      properties: [ "email", "hs_object_id" ],
      filterGroups: [
        {
          filters: [
            { propertyName: "email", operator: "EQ", value: "test@example.com" }
          ]
        }
      ]
    }

    @mock_search_api.expects(:do_search)
                   .with(public_object_search_request: expected_search_request)
                   .returns(mock_response)

    result = @client.contacts_by_email(emails)

    assert_equal 1, result.keys.length
    assert_equal "contact1", result["test@example.com"]["id"]
  end

  test "contacts_by_email handles nil or empty response gracefully" do
    emails = [ "test@example.com" ]

    @client.stubs(:get_all_property_definitions).with(:contacts).returns({})

    # Test with nil response
    @mock_search_api.stubs(:do_search).returns(nil)
    result = @client.contacts_by_email(emails)
    assert_equal({}, result)

    # Test with response without results
    mock_response = OpenStruct.new(results: nil)
    @mock_search_api.stubs(:do_search).returns(mock_response)
    result = @client.contacts_by_email(emails)
    assert_equal({}, result)
  end

  test "create_contact creates contact with email and ENRICHMENT source" do
    email = "new@example.com"

    expected_contact_input = {
      properties: {
        "email" => email,
        "hs_object_source" => "ENRICHMENT"
      }
    }

    mock_response = {
      "id" => "new_contact_123",
      "properties" => {
        "email" => email,
        "hs_object_source" => "ENRICHMENT"
      }
    }

    @mock_basic_api.expects(:create)
                   .with(simple_public_object_input: expected_contact_input)
                   .returns(mock_response)

    result = @client.create_contact(email)

    assert_equal "new_contact_123", result["id"]
    assert_equal email, result["properties"]["email"]
    assert_equal "ENRICHMENT", result["properties"]["hs_object_source"]
  end

  test "create_contact accepts additional properties" do
    email = "new@example.com"
    additional_props = { "firstname" => "John", "lastname" => "Doe" }

    expected_contact_input = {
      properties: {
        "email" => email,
        "hs_object_source" => "ENRICHMENT",
        "firstname" => "John",
        "lastname" => "Doe"
      }
    }

    mock_response = { "id" => "new_contact_456" }

    @mock_basic_api.expects(:create)
                   .with(simple_public_object_input: expected_contact_input)
                   .returns(mock_response)

    result = @client.create_contact(email, additional_props)

    assert_equal "new_contact_456", result["id"]
  end

  test "create_contact handles response with to_hash method" do
    email = "new@example.com"

    # Mock response object that responds to to_hash
    mock_response = mock("response")
    mock_response.stubs(:respond_to?).with(:to_hash).returns(true)
    mock_response.stubs(:to_hash).returns({ "id" => "hashed_contact_789" })

    @mock_basic_api.stubs(:create).returns(mock_response)

    result = @client.create_contact(email)

    assert_equal "hashed_contact_789", result["id"]
  end

  test "create_contact respects rate limiting" do
    email = "new@example.com"

    # Mock rate limit manager
    mock_rate_manager = mock("rate_manager")
    mock_rate_manager.expects(:wait_if_needed)
    mock_rate_manager.expects(:record_request)

    @client.instance_variable_get(:@rate_limit_managers)[:default] = mock_rate_manager

    mock_response = { "id" => "rate_limited_contact" }
    @mock_basic_api.stubs(:create).returns(mock_response)

    result = @client.create_contact(email)

    assert_equal "rate_limited_contact", result["id"]
  end

  test "contacts_by_email respects rate limiting" do
    emails = [ "test@example.com" ]

    # Mock rate limit manager
    mock_rate_manager = mock("rate_manager")
    mock_rate_manager.expects(:wait_if_needed)
    mock_rate_manager.expects(:record_request)

    @client.instance_variable_get(:@rate_limit_managers)[:search] = mock_rate_manager

    @client.stubs(:get_all_property_definitions).returns({})
    mock_response = OpenStruct.new(results: [])
    @mock_search_api.stubs(:do_search).returns(mock_response)

    @client.contacts_by_email(emails)
  end

  test "contacts_by_email filters out contacts without email property" do
    emails = [ "test@example.com" ]

    @client.stubs(:get_all_property_definitions).with(:contacts).returns({})

    # Mock response with contact missing email in properties
    mock_response = OpenStruct.new(
      results: [
        { "id" => "contact1", "properties" => {} }, # No email
        { "id" => "contact2", "properties" => { "email" => "test@example.com" } }
      ]
    )

    @mock_search_api.stubs(:do_search).returns(mock_response)

    result = @client.contacts_by_email(emails)

    # Should only include the contact with email
    assert_equal 1, result.keys.length
    assert_equal "contact2", result["test@example.com"]["id"]
  end
end
