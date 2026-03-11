module Connectable
  extend ActiveSupport::Concern

  included do
    encrypts :imap_username
    encrypts :imap_password
    encrypts :smtp_username
    encrypts :smtp_password

    validates :imap_server, presence: true
    validates :imap_port, presence: true
    validates :smtp_server, presence: true
    validates :smtp_port, presence: true
  end

  def with_imap_connection
    imap = Net::IMAP.new(imap_server, port: imap_port, ssl: imap_use_ssl)
    imap.login(imap_username, imap_password)
    yield imap
  ensure
    imap&.logout rescue nil
    imap&.disconnect rescue nil
  end
end
