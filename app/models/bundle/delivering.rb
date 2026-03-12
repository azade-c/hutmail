module Bundle::Delivering
  extend ActiveSupport::Concern

  def deliver!
    account = vessel.relay_account
    log_step "SMTP #{account.smtp_server}:#{account.smtp_port} (#{account.smtp_encryption}) → #{vessel.sailmail_address}"
    send_with_auth_fallback(account)
    record_as_sent!
    log_step "✅ Dépêche envoyée"
    mark_sources_processed
  rescue => e
    log_step "❌ #{e.class}: #{e.message}"

    if sent?
      save!(validate: false)
    else
      update!(status: "error", error_message: e.message)
    end

    Rails.logger.error "Bundle##{id} failed: #{e.class} #{e.message}"
  end

  def sent?
    status == "sent"
  end

  private
    def send_with_auth_fallback(account)
      ApplicationMailer::SMTP_AUTH_METHODS.each_with_index do |auth_method, index|
        log_step "Auth: #{auth_method}"
        RelayMailer.send_bundle(self, auth_method:).deliver_now
        return
      rescue Net::SMTPSyntaxError, Net::SMTPFatalError => e
        raise unless e.message.include?("mechanism") || e.message.include?("auth")
        raise if index == ApplicationMailer::SMTP_AUTH_METHODS.size - 1

        log_step "⚠️ #{auth_method} refusé, tentative suivante"
      end
    end

    def record_as_sent!
      log_step "Statut → sent (#{messages_count} messages, #{Bundle.format_size(total_stripped_size || 0)})"
      update!(status: "sent", sent_at: Time.current)
      message_digests.update_all(status: "sent")
    end

    def mark_sources_processed
      message_digests.includes(:mail_account).group_by(&:mail_account).each do |account, msgs|
        log_step "IMAP → HutMail/ (#{account.short_code}: #{msgs.size} messages)"
        account.mark_as_processed(msgs.map(&:imap_uid))
      rescue => e
        log_step "⚠️ IMAP #{account.short_code}: #{e.class} #{e.message}"
        Rails.logger.warn "Failed to process IMAP for MailAccount##{account.id}: #{e.message}"
      end
    end
end
