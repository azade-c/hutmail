require "net/imap"

# Apply the Net::IMAP::ResponseParser compatibility shim before any IMAP
# operation. See NetImapResponseCompat for the rationale.
Net::IMAP::ResponseParser.prepend(NetImapResponseCompat)

module Connectable
  extend ActiveSupport::Concern

  ENCRYPTION_MODES = %w[ssl starttls none].freeze
  SENT_FOLDER_NAMES = [ "Sent", "Sent Messages", "Sent Items", "INBOX.Sent", "Envoyés", "Messages envoyés" ].freeze

  IMAP_DEFAULT_PORTS = { "ssl" => 993, "starttls" => 143, "none" => 143 }.freeze
  SMTP_DEFAULT_PORTS = { "ssl" => 465, "starttls" => 587, "none" => 25 }.freeze

  IMAP_AUTH_METHODS = %w[plain login].freeze
  IMAP_MOVE_STRATEGIES = %w[move copy_delete_expunge].freeze

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
    validates :imap_auth_method, inclusion: { in: IMAP_AUTH_METHODS }, allow_nil: true
    validates :imap_move_strategy, inclusion: { in: IMAP_MOVE_STRATEGIES }, allow_nil: true

    before_validation :apply_default_ports
    before_validation :reset_smtp_auth_method, if: :smtp_config_changed?
    before_validation :reset_imap_auth_method, if: :imap_config_changed?
    before_validation :reset_imap_move_strategy, if: :imap_config_changed?
  end

  # Password fields are rendered blank in edit forms (we never echo secrets
  # back into the DOM). Treat a blank submission on an existing record as
  # "leave unchanged" so saving unrelated settings does not wipe the stored
  # credentials. New records still receive blanks so presence validations
  # fire as expected.
  def imap_password=(value)
    return if value.blank? && persisted?
    super
  end

  def smtp_password=(value)
    return if value.blank? && persisted?
    super
  end

  def mark_as_processed(imap_uids)
    return if imap_uids.empty?

    folder = self.class::PROCESSED_FOLDER
    with_imap_connection do |imap|
      imap.select("INBOX")
      ensure_folder(imap, folder)
      imap.uid_store(imap_uids, "+FLAGS", [ :Seen ])
      apply_imap_move_strategy(imap, imap_uids, folder)
    end
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
    authenticate_imap(imap)
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
    def ensure_folder(imap, name)
      imap.create(name)
    rescue Net::IMAP::NoResponseError
    end

    def apply_imap_move_strategy(imap, uids, folder)
      capabilities = imap.capability
      strategy = imap_move_strategy.presence || resolve_move_strategy(capabilities)

      if strategy == "move"
        imap.uid_move(uids, folder)
        strategy
      else
        copy_delete_expunge(imap, uids, folder, capabilities:)
        strategy
      end
    rescue Net::IMAP::BadResponseError, Net::IMAP::NoResponseError
      if strategy == "move"
        update_column(:imap_move_strategy, "copy_delete_expunge")
        copy_delete_expunge(imap, uids, folder, capabilities:)
        "copy_delete_expunge"
      else
        raise
      end
    end

    def resolve_move_strategy(capabilities)
      if capabilities.include?("MOVE")
        update_column(:imap_move_strategy, "move")
        "move"
      else
        update_column(:imap_move_strategy, "copy_delete_expunge")
        "copy_delete_expunge"
      end
    end

    def copy_delete_expunge(imap, uids, folder, capabilities: nil)
      imap.uid_copy(uids, folder)
      imap.uid_store(uids, "+FLAGS", [ :Deleted ])

      caps = capabilities || imap.capability
      if caps.include?("UIDPLUS")
        imap.uid_expunge(uids)
      else
        imap.expunge
      end
    end

    # NOTE: retries auth on the same TCP connection after failure.
    # RFC 3501 §6.2 allows this, but some servers (old Dovecot, Exchange)
    # may reject. If that happens, we'd need to reconnect before retrying.
    def authenticate_imap(imap)
      if imap_auth_method.present?
        perform_imap_auth(imap, imap_auth_method)
      else
        authenticate_imap_with_fallback(imap)
      end
    rescue Net::IMAP::NoResponseError, Net::IMAP::BadResponseError
      raise unless imap_auth_method.present?
      failed_method = imap_auth_method
      update_column(:imap_auth_method, nil) # bypass validations/callbacks intentionally
      authenticate_imap_with_fallback(imap, skip: failed_method)
    end

    def authenticate_imap_with_fallback(imap, skip: nil)
      methods = skip ? IMAP_AUTH_METHODS.reject { |m| m == skip } : IMAP_AUTH_METHODS
      methods.each_with_index do |method, index|
        perform_imap_auth(imap, method)
        update_column(:imap_auth_method, method) # bypass callbacks to avoid reset loop
        return
      rescue Net::IMAP::NoResponseError, Net::IMAP::BadResponseError
        raise if index == methods.size - 1
      end
    end

    def perform_imap_auth(imap, method)
      if method == "login"
        imap.login(imap_username, imap_password)
      else
        imap.authenticate("PLAIN", imap_username, imap_password)
      end
    end

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

    def reset_imap_auth_method
      self.imap_auth_method = nil
    end

    def reset_imap_move_strategy
      self.imap_move_strategy = nil if respond_to?(:imap_move_strategy=)
    end

    def smtp_config_changed?
      smtp_server_changed? || smtp_port_changed? || smtp_encryption_changed?
    end

    def imap_config_changed?
      imap_server_changed? || imap_port_changed? || imap_encryption_changed? ||
        imap_username_changed? || imap_password_changed?
    end

    def apply_default_ports
      self.imap_port ||= IMAP_DEFAULT_PORTS[imap_encryption]
      self.smtp_port ||= SMTP_DEFAULT_PORTS[smtp_encryption]
    end
end
