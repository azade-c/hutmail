class ApplicationMailer < ActionMailer::Base
  default from: "from@example.com"
  layout "mailer"

  private
    def smtp_options_for(account)
      options = {
        address: account.smtp_server,
        port: account.smtp_port,
        enable_starttls_auto: account.smtp_use_starttls
      }

      if account.smtp_username.present?
        options[:user_name] = account.smtp_username
        options[:password] = account.smtp_password
        options[:authentication] = :plain
      end

      options
    end
end
