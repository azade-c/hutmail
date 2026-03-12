class ApplicationMailer < ActionMailer::Base
  default from: "from@example.com"
  layout "mailer"

  SMTP_OPEN_TIMEOUT = 10
  SMTP_READ_TIMEOUT = 30

  private
    def smtp_options_for(account)
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
        options[:authentication] = :plain
      end

      options
    end
end
