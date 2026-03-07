class CollectedMessage < ApplicationRecord
  belongs_to :mail_account
  belongs_to :bundle, optional: true

  encrypts :from_address
  encrypts :from_name
  encrypts :to_address
  encrypts :subject
  encrypts :stripped_body

  scope :pending, -> { where(status: "pending") }
  scope :sent, -> { where(status: "sent") }
  scope :dropped, -> { where(status: "dropped") }
  scope :oldest_first, -> { order(date: :asc) }

  validates :hutmail_id, presence: true, uniqueness: true
  validates :imap_message_id, presence: true, uniqueness: { scope: :mail_account_id }
  validates :status, presence: true, inclusion: { in: %w[pending sent dropped] }

  def user
    mail_account.user
  end

  def short_code
    mail_account.short_code
  end
end
