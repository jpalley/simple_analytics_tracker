class FacebookAudienceSync < ApplicationRecord
  validates :table_name, :audience_name, presence: true
  has_many :facebook_audience_sync_histories, dependent: :destroy
  has_many :facebook_audience_sync_users, dependent: :destroy

  def status
    # Default status based on whether it has sync histories
    if facebook_audience_sync_histories.any?
      "completed"
    else
      "pending"
    end
  end

  def number_of_records
    # Return total records synced from histories
    facebook_audience_sync_histories.sum(:records_synced)
  end

  def latest_sync
    facebook_audience_sync_histories.order(created_at: :desc).first
  end

  def synced_users_count
    facebook_audience_sync_users.count
  end
end
