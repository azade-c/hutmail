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
      {
        address: account.smtp_server,
        port: account.smtp_port,
        user_name: account.smtp_username,
        password: account.smtp_password,
        enable_starttls_auto: account.smtp_use_starttls,
        authentication: :plain,
      }
    end
end
