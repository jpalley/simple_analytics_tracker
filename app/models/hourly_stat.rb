class HourlyStat < ApplicationRecord
  validates :hour, presence: true, uniqueness: true
  scope :ordered, -> { order(:hour) }
end
