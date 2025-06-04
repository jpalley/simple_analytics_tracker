class FacebookAudienceSyncHistory < ApplicationRecord
  belongs_to :facebook_audience_sync

  scope :successful, -> { where(error_message: nil) }
  scope :failed, -> { where.not(error_message: nil) }
end
