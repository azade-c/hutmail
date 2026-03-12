class OutboundMailer < ApplicationMailer
  def send_reply(vessel_reply, auth_method: nil)
    @reply = vessel_reply
    account = vessel_reply.mail_account

    mail(
      from: account.smtp_username,
      to: vessel_reply.to_address,
      subject: vessel_reply.subject || "HutMail reply",
      body: vessel_reply.body,
      content_type: "text/plain",
      delivery_method_options: smtp_options_for(account, auth_method:),
    )
  end
end
