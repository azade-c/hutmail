class OutboundMailer < ApplicationMailer
  def send_reply(vessel_reply)
    @reply = vessel_reply
    account = vessel_reply.mail_account

    mail(
      from: account.smtp_username,
      to: vessel_reply.to_address,
      subject: "Re: #{original_subject(vessel_reply)}",
      body: vessel_reply.body,
      content_type: "text/plain"
    )
  end

  private

  def original_subject(reply)
    original = CollectedMessage
      .where(from_address: reply.to_address, mail_account: reply.mail_account)
      .order(date: :desc)
      .first

    original&.subject || "HutMail reply"
  end
end
