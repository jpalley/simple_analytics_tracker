class HubspotSyncStatus < ApplicationRecord
  # object_type: string - the type of object being synced (contacts, companies, etc.)
  # status: string - success, error, in_progress
  # record_count: integer - number of records synced
  # error_message: text - error message if status is error
  # synced_at: datetime - when the sync was completed

  validates :object_type, presence: true
  validates :status, presence: true, inclusion: { in: %w[success error in_progress] }

  scope :recent, -> { order(created_at: :desc).limit(10) }
  scope :for_object, ->(object_type) { where(object_type: object_type) }
  scope :successful, -> { where(status: "success") }
  scope :failed, -> { where(status: "error") }
  scope :in_progress, -> { where(status: "in_progress") }

  def self.create_or_update(attributes)
    status = find_or_initialize_by(object_type: attributes[:object_type])
    status.assign_attributes(attributes)
    status.save!
    status
  end

  def self.last_successful_sync(object_type)
    for_object(object_type).successful.order(synced_at: :desc).first
  end

  def self.last_sync(object_type)
    for_object(object_type).order(created_at: :desc).first
  end

  def successful?
    status == "success"
  end

  def failed?
    status == "error"
  end

  def in_progress?
    status == "in_progress"
  end
end
