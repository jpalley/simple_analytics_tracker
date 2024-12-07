class FacebookSync < ApplicationRecord
  validates :table_name, :event_name, :event_value, :event_source_url, presence: true
  has_many :facebook_sync_histories
end
