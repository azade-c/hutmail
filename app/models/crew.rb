class Crew < ApplicationRecord
  belongs_to :user
  belongs_to :vessel

  validates :role, presence: true, inclusion: { in: %w[captain shore_agent] }
  validates :user_id, uniqueness: { scope: :vessel_id }
end
