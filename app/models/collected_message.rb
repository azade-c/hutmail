class CollectedMessage < ApplicationRecord
  include CollectedMessage::Strippable
  include CollectedMessage::Identifiable
  include CollectedMessage::Presentable

  belongs_to :mail_account
  belongs_to :bundle, optional: true

  encrypts :subject
  encrypts :stripped_body

  scope :pending, -> { where(status: "pending") }
  scope :sent, -> { where(status: "sent") }
  scope :dropped, -> { where(status: "dropped") }
  scope :oldest_first, -> { order(date: :asc) }

  validates :hutmail_id, presence: true, uniqueness: true
  validates :imap_message_id, presence: true, uniqueness: { scope: :mail_account_id }
  validates :status, presence: true, inclusion: { in: %w[pending sent dropped] }

  def vessel
    mail_account.vessel
  end

  def short_code
    mail_account.short_code
  end
end
