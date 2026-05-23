class OutboundMailer < ApplicationMailer
  def send_reply(vessel_reply, auth_method: nil)
    @reply = vessel_reply
    account = vessel_reply.mail_account

    mail(
      {
        from: account.smtp_username,
        to: vessel_reply.to_address,
        subject: vessel_reply.subject || "Hutmail reply",
        body: vessel_reply.body,
        content_type: "text/plain",
        delivery_method_options: smtp_options_for(account, auth_method:)
      }.merge(threading_headers_for(vessel_reply))
    )
  end

  private
    def threading_headers_for(vessel_reply)
      original = vessel_reply.message_digest
      return {} unless original&.imap_message_id.present?

      reference = Mail::Utilities.bracket(original.imap_message_id)
      { "In-Reply-To" => reference, "References" => reference }
    end
end
