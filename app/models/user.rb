class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :crews, dependent: :destroy
  has_many :vessels, through: :crews

  validates :email_address, presence: true, uniqueness: true
  validates :password, length: { minimum: 12 }, on: :create

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  def primary_vessel
    vessels.first
  end
end
