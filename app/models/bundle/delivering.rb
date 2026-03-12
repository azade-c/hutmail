module Bundle::Delivering
  extend ActiveSupport::Concern

  def deliver!
    account = vessel.relay_account
    log_step "SMTP #{account.smtp_server}:#{account.smtp_port} (#{account.smtp_encryption}) → #{vessel.sailmail_address}"

    RelayMailer.new.deliver_with_auth_fallback(account) do |auth_method|
      log_step "Auth: #{auth_method}"
      RelayMailer.send_bundle(self, auth_method:)
    end

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
  ensure
    save_dispatch_log
  end

  def sent?
    status == "sent"
  end

  private
    def record_as_sent!
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

    def save_dispatch_log
      update_column(:dispatch_log, dispatch_log) if persisted? && dispatch_log_changed?
    rescue => e
      Rails.logger.error "Bundle##{id} failed to save dispatch log: #{e.message}"
    end
end
