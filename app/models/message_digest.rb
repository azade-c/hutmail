class MessageDigest < ApplicationRecord
  include MessageDigest::Stripping
  include MessageDigest::Identifiable
  include MessageDigest::Presentable

  belongs_to :mail_account
  has_many :bundle_items, dependent: :destroy
  has_many :bundles, through: :bundle_items

  encrypts :subject
  encrypts :stripped_body

  scope :pending, -> { where(status: "pending") }
  scope :bundleable, -> { where(status: %w[pending resend]) }
  scope :sent, -> { where(status: "sent") }
  scope :dropped, -> { where(status: "dropped") }
  scope :ordered, -> { order(id: :asc) }

  validates :hutmail_id, presence: true, uniqueness: true
  validates :imap_message_id, presence: true, uniqueness: { scope: :mail_account_id }
  validates :status, presence: true, inclusion: { in: %w[pending sent dropped resend] }

  def vessel
    mail_account.vessel
  end

  def short_code
    mail_account.short_code
  end
end
