require "test_helper"

class FacebookSyncTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end

  test "status should be pending if no histories exist" do
    sync = facebook_syncs(:one)
    sync.facebook_sync_histories.destroy_all
    assert_equal "pending", sync.status
  end

  test "status should be completed if histories exist" do
    sync = facebook_syncs(:one)
    sync.facebook_sync_histories.create!(conversions: 5)
    assert_equal "completed", sync.status
  end

  test "number_of_events should sum conversions from histories" do
    sync = facebook_syncs(:one)
    sync.facebook_sync_histories.destroy_all
    sync.facebook_sync_histories.create!(conversions: 3)
    sync.facebook_sync_histories.create!(conversions: 7)
    assert_equal 10, sync.number_of_events
  end
end
