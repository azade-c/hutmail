class MailAccount < ApplicationRecord
  belongs_to :user

  encrypts :imap_password

  validates :name, presence: true
  validates :imap_server, presence: true
  validates :imap_port, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :imap_username, presence: true
  validates :imap_password, presence: true
end
