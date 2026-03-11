module Connectable
  extend ActiveSupport::Concern

  ENCRYPTION_MODES = %w[ssl starttls none].freeze

  IMAP_DEFAULT_PORTS = { "ssl" => 993, "starttls" => 143, "none" => 143 }.freeze
  SMTP_DEFAULT_PORTS = { "ssl" => 465, "starttls" => 587, "none" => 25 }.freeze

  included do
    encrypts :imap_username
    encrypts :imap_password
    encrypts :smtp_username
    encrypts :smtp_password

    validates :imap_server, presence: true
    validates :imap_port, presence: true
    validates :imap_encryption, presence: true, inclusion: { in: ENCRYPTION_MODES }
    validates :smtp_server, presence: true
    validates :smtp_port, presence: true
    validates :smtp_encryption, presence: true, inclusion: { in: ENCRYPTION_MODES }

    before_validation :apply_default_ports
  end

  def with_imap_connection
    imap = Net::IMAP.new(imap_server, port: imap_port, ssl: imap_encryption == "ssl")
    imap.starttls if imap_encryption == "starttls"
    imap.login(imap_username, imap_password)
    yield imap
  ensure
    imap&.logout rescue nil
    imap&.disconnect rescue nil
  end

  private
    def apply_default_ports
      self.imap_port ||= IMAP_DEFAULT_PORTS[imap_encryption]
      self.smtp_port ||= SMTP_DEFAULT_PORTS[smtp_encryption]
    end
end
