class OutboundMailer < ApplicationMailer
  def send_reply(boat_reply)
    @reply = boat_reply
    account = boat_reply.mail_account

    mail(
      from: account.smtp_username,
      to: boat_reply.to_address,
      subject: "Re: #{original_subject(boat_reply)}",
      body: boat_reply.body,
      content_type: "text/plain"
    )
  end

  private

  def original_subject(reply)
    # Find the most recent message from this recipient to build a Re: subject
    original = CollectedMessage
      .where(from_address: reply.to_address, mail_account: reply.mail_account)
      .order(date: :desc)
      .first

    original&.subject || "HutMail reply"
  end
end
