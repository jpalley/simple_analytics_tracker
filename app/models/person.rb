class Person < ApplicationRecord
  has_many :events, dependent: :destroy, primary_key: "uuid", foreign_key: "uuid"

  # Store initial and latest URL parameters dynamically

  # Validations
  validates :uuid, presence: true, uniqueness: true
end
