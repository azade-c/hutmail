class OutboundMailer < ApplicationMailer
  def send_reply(vessel_reply)
    @reply = vessel_reply
    account = vessel_reply.mail_account

    mail(
      from: account.smtp_username,
      to: vessel_reply.to_address,
      subject: vessel_reply.subject || "HutMail reply",
      body: vessel_reply.body,
      content_type: "text/plain",
      delivery_method_options: smtp_options_for(account),
    )
  end

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
