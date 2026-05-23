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
      }
        .merge(hutmail_headers(kind: :vessel_reply, vessel: vessel_reply.vessel, reply_id: vessel_reply.id))
        .merge(threading_headers_for(vessel_reply))
    )
  end

  private
    def threading_headers_for(vessel_reply)
      original = vessel_reply.message_digest
      return {} unless original&.imap_message_id.present?

      reference = formatted_message_id(original.imap_message_id)
      { "In-Reply-To" => reference, "References" => reference }
    end

    def formatted_message_id(raw)
      raw = raw.to_s.strip
      raw.start_with?("<") ? raw : "<#{raw}>"
    end
end
