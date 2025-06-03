require "test_helper"

class HubspotSyncJobTest < ActiveJob::TestCase
  setup do
    @original_access_token = ENV["HUBSPOT_ACCESS_TOKEN"]
    ENV["HUBSPOT_ACCESS_TOKEN"] = "test_token"

    # Mock HubSpot client
    @mock_hubspot_client = mock("hubspot_client")
    HubspotClient.stubs(:new).returns(@mock_hubspot_client)

    @job = HubspotSyncJob.new
  end

  teardown do
    ENV["HUBSPOT_ACCESS_TOKEN"] = @original_access_token
  end

  test "skips processing when HUBSPOT_ACCESS_TOKEN is blank" do
    ENV["HUBSPOT_ACCESS_TOKEN"] = ""

    @mock_hubspot_client.expects(:contacts_by_utk).never
    @mock_hubspot_client.expects(:contacts_by_email).never

    HubspotSyncJob.perform_now
  end

  test "process_utk_batch processes UTK-based sync successfully" do
    person_with_utk = Person.create!(
      uuid: "test-uuid-1",
      properties: { "hubspotutk" => "test-utk-123" }
    )

    batch = [ person_with_utk ]

    # Mock UTK response
    utk_response = {
      "test-utk-123" => { "vid" => "12345", "is-contact" => true }
    }
    @mock_hubspot_client.expects(:contacts_by_utk).with([ "test-utk-123" ]).returns(utk_response)

    @job.send(:process_utk_batch, batch)

    assert_equal "12345", person_with_utk.properties["hubspot_contact_id"]
  ensure
    person_with_utk&.destroy
  end

  test "process_utk_batch skips people without UTK" do
    person_without_utk = Person.create!(
      uuid: "test-uuid-2",
      properties: { "email" => "test@example.com" }
    )

    batch = [ person_without_utk ]

    @mock_hubspot_client.expects(:contacts_by_utk).never

    @job.send(:process_utk_batch, batch)

    assert_nil person_without_utk.properties["hubspot_contact_id"]
  ensure
    person_without_utk&.destroy
  end

  test "process_email_batch links existing HubSpot contact" do
    person_with_email = Person.create!(
      uuid: "test-uuid-3",
      properties: { "email" => "existing@example.com" }
    )

    batch = [ person_with_email ]

    email_response = {
      "existing@example.com" => {
        "id" => "existing-contact-123",
        "properties" => { "email" => "existing@example.com" }
      }
    }
    @mock_hubspot_client.expects(:contacts_by_email).with([ "existing@example.com" ]).returns(email_response)

    @job.send(:process_email_batch, batch)

    assert_equal "existing-contact-123", person_with_email.properties["hubspot_contact_id"]
  ensure
    person_with_email&.destroy
  end

  test "process_email_batch creates new contact when email doesn't exist" do
    person_with_email = Person.create!(
      uuid: "test-uuid-4",
      properties: { "email" => "new@example.com" }
    )

    batch = [ person_with_email ]

    @mock_hubspot_client.expects(:contacts_by_email).with([ "new@example.com" ]).returns({})

    new_contact_response = { "id" => "new-contact-789" }
    @mock_hubspot_client.expects(:create_contact).with("new@example.com").returns(new_contact_response)

    @job.send(:process_email_batch, batch)

    assert_equal "new-contact-789", person_with_email.properties["hubspot_contact_id"]
  ensure
    person_with_email&.destroy
  end

  test "process_email_batch skips people without email" do
    person_without_email = Person.create!(
      uuid: "test-uuid-5",
      properties: { "name" => "No Email" }
    )

    batch = [ person_without_email ]

    @mock_hubspot_client.expects(:contacts_by_email).never
    @mock_hubspot_client.expects(:create_contact).never

    @job.send(:process_email_batch, batch)

    assert_nil person_without_email.properties["hubspot_contact_id"]
  ensure
    person_without_email&.destroy
  end

  test "process_email_batch skips people who already have hubspot_contact_id" do
    person_with_existing_id = Person.create!(
      uuid: "test-uuid-6",
      properties: {
        "email" => "existing@example.com",
        "hubspot_contact_id" => "already-linked-123"
      }
    )

    batch = [ person_with_existing_id ]

    @mock_hubspot_client.expects(:contacts_by_email).never
    @mock_hubspot_client.expects(:create_contact).never

    @job.send(:process_email_batch, batch)

    assert_equal "already-linked-123", person_with_existing_id.properties["hubspot_contact_id"]
  ensure
    person_with_existing_id&.destroy
  end

  test "process_email_batch handles contact creation failure gracefully" do
    person_with_email = Person.create!(
      uuid: "test-uuid-7",
      properties: { "email" => "failing@example.com" }
    )

    batch = [ person_with_email ]

    @mock_hubspot_client.expects(:contacts_by_email).with([ "failing@example.com" ]).returns({})
    @mock_hubspot_client.expects(:create_contact).with("failing@example.com").raises(StandardError.new("API Error"))

    # Should not raise error
    assert_nothing_raised do
      @job.send(:process_email_batch, batch)
    end

    assert_nil person_with_email.properties["hubspot_contact_id"]
  ensure
    person_with_email&.destroy
  end

  test "process_email_batch uses hs_object_id when id is not available" do
    person_with_email = Person.create!(
      uuid: "test-uuid-8",
      properties: { "email" => "hs_object@example.com" }
    )

    batch = [ person_with_email ]

    email_response = {
      "hs_object@example.com" => {
        "hs_object_id" => "hs-object-123",
        "properties" => { "email" => "hs_object@example.com" }
      }
    }
    @mock_hubspot_client.expects(:contacts_by_email).with([ "hs_object@example.com" ]).returns(email_response)

    @job.send(:process_email_batch, batch)

    assert_equal "hs-object-123", person_with_email.properties["hubspot_contact_id"]
  ensure
    person_with_email&.destroy
  end

  test "process_email_batch deduplicates emails" do
    person1 = Person.create!(
      uuid: "dup-1",
      properties: { "email" => "duplicate@example.com" }
    )
    person2 = Person.create!(
      uuid: "dup-2",
      properties: { "email" => "duplicate@example.com" }
    )

    batch = [ person1, person2 ]

    # Should only call with unique emails
    @mock_hubspot_client.expects(:contacts_by_email).with([ "duplicate@example.com" ]).returns({})
    @mock_hubspot_client.expects(:create_contact).with("duplicate@example.com").returns({ "id" => "dup-contact" }).once

    @job.send(:process_email_batch, batch)

    assert_equal "dup-contact", person1.properties["hubspot_contact_id"]
    assert_equal "dup-contact", person2.properties["hubspot_contact_id"]
  ensure
    person1&.destroy
    person2&.destroy
  end

  test "process_batch processes both UTK and email sync" do
    person_with_utk = Person.create!(
      uuid: "mixed-utk",
      properties: { "hubspotutk" => "mixed-utk-123" }
    )

    person_with_email = Person.create!(
      uuid: "mixed-email",
      properties: { "email" => "mixed@example.com" }
    )

    batch = [ person_with_utk, person_with_email ]

    # Mock UTK response
    utk_response = {
      "mixed-utk-123" => { "vid" => "mixed-utk-contact", "is-contact" => true }
    }
    @mock_hubspot_client.expects(:contacts_by_utk).with([ "mixed-utk-123" ]).returns(utk_response)

    # Mock email response
    email_response = {
      "mixed@example.com" => {
        "id" => "mixed-email-contact",
        "properties" => { "email" => "mixed@example.com" }
      }
    }
    @mock_hubspot_client.expects(:contacts_by_email).with([ "mixed@example.com" ]).returns(email_response)

    @job.send(:process_batch, batch)

    assert_equal "mixed-utk-contact", person_with_utk.properties["hubspot_contact_id"]
    assert_equal "mixed-email-contact", person_with_email.properties["hubspot_contact_id"]
    assert_not_nil person_with_utk.hubspot_synced_at
    assert_not_nil person_with_email.hubspot_synced_at
  ensure
    person_with_utk&.destroy
    person_with_email&.destroy
  end

  test "process_batch UTK sync takes precedence over email sync" do
    person_with_both = Person.create!(
      uuid: "both-contact",
      properties: {
        "email" => "both@example.com",
        "hubspotutk" => "both-utk-456"
      }
    )

    batch = [ person_with_both ]

    # Mock responses - UTK should take precedence
    utk_response = {
      "both-utk-456" => { "vid" => "utk-contact-456", "is-contact" => true }
    }
    @mock_hubspot_client.expects(:contacts_by_utk).with([ "both-utk-456" ]).returns(utk_response)

    # Email sync should not process this person since UTK already linked it - no email call expected

    @job.send(:process_batch, batch)

    assert_equal "utk-contact-456", person_with_both.properties["hubspot_contact_id"]
  ensure
    person_with_both&.destroy
  end
end
