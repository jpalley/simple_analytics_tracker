class Event < ApplicationRecord
  belongs_to :person, primary_key: "uuid", foreign_key: "uuid", optional: true


  # Validations
  validates :uuid, :event_type, :timestamp, presence: true

  before_validation :set_timestamp, on: :create

  private

  def set_timestamp
    self.timestamp ||= Time.current
  end
end
