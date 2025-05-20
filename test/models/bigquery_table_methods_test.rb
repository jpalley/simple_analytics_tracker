require "test_helper"
require "google/cloud/bigquery"

class BigqueryTableMethodsTest < ActiveSupport::TestCase
  test "check google-cloud-bigquery compatibility with our views" do
    # Define what methods we're using in our views
    view_methods = [
      :table_id,
      :description,
      :created_at,
      :modified_at,
      :project_id,
      :dataset_id
    ]

    # Define available methods according to documentation
    available_methods = [
      :table_id,
      :description,
      :created_at,
      :modified_at,
      :project_id,
      :dataset_id,
      :rows_count,    # correct method for row count
      :bytes_count    # correct method for byte size
    ]

    # Check if the methods we use in views are actually available
    view_methods.each do |method|
      assert available_methods.include?(method), "#{method} is used in views but not available in Google::Cloud::Bigquery::Table"
    end

    # Check for incorrect method usage
    refute available_methods.include?(:num_rows), "num_rows is not available in Google::Cloud::Bigquery::Table, use rows_count instead"
    refute available_methods.include?(:num_bytes), "num_bytes is not available in Google::Cloud::Bigquery::Table, use bytes_count instead"

    # Document the correct methods to use
    assert available_methods.include?(:rows_count), "Use rows_count instead of num_rows"
    assert available_methods.include?(:bytes_count), "Use bytes_count instead of num_bytes"
  end
end
