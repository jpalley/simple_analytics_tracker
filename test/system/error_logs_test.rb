require "application_system_test_case"

class ErrorLogsTest < ApplicationSystemTestCase
  setup do
    @error_log = error_logs(:one)
  end

  test "visiting the index" do
    visit error_logs_url
    assert_selector "h1", text: "Error logs"
  end

  test "should create error log" do
    visit error_logs_url
    click_on "New error log"

    fill_in "Body", with: @error_log.body
    fill_in "Title", with: @error_log.title
    click_on "Create Error log"

    assert_text "Error log was successfully created"
    click_on "Back"
  end

  test "should update Error log" do
    visit error_log_url(@error_log)
    click_on "Edit this error log", match: :first

    fill_in "Body", with: @error_log.body
    fill_in "Title", with: @error_log.title
    click_on "Update Error log"

    assert_text "Error log was successfully updated"
    click_on "Back"
  end

  test "should destroy Error log" do
    visit error_log_url(@error_log)
    click_on "Destroy this error log", match: :first

    assert_text "Error log was successfully destroyed"
  end
end
