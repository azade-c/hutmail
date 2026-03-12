module Bundle::Delivering
  extend ActiveSupport::Concern

  def deliver!
    account = vessel.relay_account
    log_step "SMTP #{account.smtp_server}:#{account.smtp_port} (#{account.smtp_encryption}) → #{vessel.sailmail_address}"

    message = RelayMailer.new.deliver_with_auth_fallback(account) do |auth_method|
      log_step "Auth: #{auth_method}"
      RelayMailer.send_bundle(self, auth_method:)
    end

    append_to_sent(account, message)
    record_as_sent!
    log_step "✅ Dépêche acceptée par le SMTP"
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
    def append_to_sent(account, message)
      folder = account.append_to_sent(message.message.to_s)
      log_step "IMAP APPEND → #{folder}"
    rescue => e
      log_step "⚠️ IMAP APPEND: #{e.class} #{e.message}"
      Rails.logger.warn "Bundle##{id} failed to append sent copy: #{e.message}"
    end

    def record_as_sent!
      update!(status: "sent", sent_at: Time.current)
      message_digests.update_all(status: MessageDigest.statuses.fetch("bundled"))
      log_step "Statut → sent (#{messages_count} messages, #{Bundle.format_size(total_stripped_size || 0)})"
    end

    def mark_sources_processed
      message_digests.includes(:mail_account).group_by(&:mail_account).each do |account, msgs|
        result = account.mark_as_processed(msgs.map(&:imap_uid))

        if result[:strategy] == "move"
          log_step "IMAP MOVE → HutMail/ (#{account.short_code}: #{msgs.size} messages)"
        else
          log_step "⚠️ MOVE non supporté, fallback COPY+DELETE+EXPUNGE"
          log_step "IMAP COPY+DELETE → HutMail/ (#{account.short_code}: #{msgs.size} messages)"
        end
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
