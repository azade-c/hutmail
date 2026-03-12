class MessageDigest < ApplicationRecord
  include MessageDigest::Stripping
  include MessageDigest::Identifiable
  include MessageDigest::Presentable

  BUNDLEABLE_STATUSES = %w[collected requeued].freeze

  enum :status, %w[collected no_longer_collectable bundled requeued].index_by(&:itself), validate: true

  belongs_to :mail_account
  has_many :bundle_items, dependent: :destroy
  has_many :bundles, through: :bundle_items

  encrypts :subject
  encrypts :stripped_body

  scope :bundleable, -> { where(status: BUNDLEABLE_STATUSES) }
  scope :ordered, -> { order(id: :asc) }

  validates :hutmail_id, presence: true, uniqueness: true
  validates :imap_message_id, presence: true, uniqueness: { scope: :mail_account_id }

  def vessel
    mail_account.vessel
  end

  def short_code
    mail_account.short_code
  end
end
