class ApplicationMailer < ActionMailer::Base
  default from: "from@example.com"
  layout "mailer"

  SMTP_OPEN_TIMEOUT = 10
  SMTP_READ_TIMEOUT = 30

  SMTP_AUTH_METHODS = %i[plain login].freeze

  def deliver_with_auth_fallback(account, &block)
    methods_to_try = if account.smtp_auth_method.present?
      [ account.smtp_auth_method.to_sym ]
    else
      SMTP_AUTH_METHODS
    end

    methods_to_try.each_with_index do |auth_method, index|
      message = block.call(auth_method)
      message.deliver_now
      account.update_column(:smtp_auth_method, auth_method.to_s) if account.smtp_auth_method.blank?
      return message
    rescue Net::SMTPSyntaxError, Net::SMTPFatalError => e
      raise unless e.message.include?("mechanism") || e.message.include?("auth")
      raise if index == methods_to_try.size - 1
    end
  end

  private
    def smtp_options_for(account, auth_method: nil)
      options = {
        address: account.smtp_server,
        port: account.smtp_port,
        open_timeout: SMTP_OPEN_TIMEOUT,
        read_timeout: SMTP_READ_TIMEOUT
      }

      case account.smtp_encryption
      when "ssl"
        options[:tls] = true
        options[:enable_starttls_auto] = false
      when "starttls"
        options[:tls] = false
        options[:enable_starttls_auto] = true
      else
        options[:tls] = false
        options[:enable_starttls_auto] = false
      end

      if account.smtp_username.present?
        options[:user_name] = account.smtp_username
        options[:password] = account.smtp_password
        options[:authentication] = auth_method || :plain
      end

      options
    end
end
