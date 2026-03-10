class RelayAccount < ApplicationRecord
  belongs_to :vessel

  encrypts :imap_username
  encrypts :imap_password
  encrypts :smtp_username
  encrypts :smtp_password

  validates :imap_server, presence: true
  validates :imap_port, presence: true
  validates :imap_username, presence: true
  validates :imap_password, presence: true
  validates :smtp_server, presence: true
  validates :smtp_port, presence: true
  validates :smtp_username, presence: true
  validates :smtp_password, presence: true
end
