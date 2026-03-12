module Connectable
  extend ActiveSupport::Concern

  ENCRYPTION_MODES = %w[ssl starttls none].freeze
  SENT_FOLDER_NAMES = [ "Sent", "Sent Messages", "Sent Items", "INBOX.Sent", "Envoyés", "Messages envoyés" ].freeze

  IMAP_DEFAULT_PORTS = { "ssl" => 993, "starttls" => 143, "none" => 143 }.freeze
  SMTP_DEFAULT_PORTS = { "ssl" => 465, "starttls" => 587, "none" => 25 }.freeze

  IMAP_OPEN_TIMEOUT = 10
  IMAP_IDLE_TIMEOUT = 30

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
    before_validation :reset_smtp_auth_method, if: :smtp_config_changed?
    before_validation :reset_imap_move_strategy, if: :imap_config_changed?
  end

  def with_imap_connection
    imap = Net::IMAP.new(
      imap_server,
      port: imap_port,
      ssl: imap_encryption == "ssl",
      open_timeout: IMAP_OPEN_TIMEOUT,
      idle_response_timeout: IMAP_IDLE_TIMEOUT
    )
    imap.starttls if imap_encryption == "starttls"
    imap.login(imap_username, imap_password)
    yield imap
  ensure
    imap&.logout rescue nil
    imap&.disconnect rescue nil
  end

  def append_to_sent(raw_message)
    with_imap_connection do |imap|
      folder = sent_folder_for(imap)
      imap.append(folder, raw_message, [ :Seen ], Time.current)
      folder
    end
  end

  private
    def sent_folder_for(imap)
      mailbox_names = Array(imap.list("", "*")).filter_map(&:name)
      special_use = mailbox_names.find { |name| name.match?(/sent/i) || name.match?(/envoy/i) }
      return special_use if special_use.present?

      SENT_FOLDER_NAMES.each do |name|
        return name if mailbox_names.include?(name)
      end

      fallback = "Sent"
      imap.create(fallback)
      fallback
    rescue Net::IMAP::NoResponseError
      fallback
    end

    def reset_smtp_auth_method
      self.smtp_auth_method = nil
    end

    def reset_imap_move_strategy
      self.imap_move_strategy = nil if respond_to?(:imap_move_strategy=)
    end

    def smtp_config_changed?
      smtp_server_changed? || smtp_port_changed? || smtp_encryption_changed?
    end

    def imap_config_changed?
      imap_server_changed? || imap_port_changed? || imap_encryption_changed?
    end

    def apply_default_ports
      self.imap_port ||= IMAP_DEFAULT_PORTS[imap_encryption]
      self.smtp_port ||= SMTP_DEFAULT_PORTS[smtp_encryption]
    end
end
