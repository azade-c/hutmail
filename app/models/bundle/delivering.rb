module Bundle::Delivering
  extend ActiveSupport::Concern

  def deliver!
    log_step "Envoi SMTP vers #{vessel.sailmail_address}"
    RelayMailer.send_bundle(self).deliver_now
    record_as_sent!
    log_step "✅ Dépêche envoyée"
    mark_sources_processed
  rescue => e
    log_step "❌ Erreur : #{e.message}"

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
    def record_as_sent!
      log_step "Statut → sent (#{messages_count} messages, #{Bundle.format_size(total_stripped_size || 0)})"
      update!(status: "sent", sent_at: Time.current)
      message_digests.update_all(status: "sent")
    end

    def mark_sources_processed
      message_digests.includes(:mail_account).group_by(&:mail_account).each do |account, msgs|
        log_step "Déplacement IMAP → HutMail/ (#{account.short_code}: #{msgs.size} messages)"
        account.mark_as_processed(msgs.map(&:imap_uid))
      rescue => e
        log_step "⚠️ IMAP #{account.short_code} : #{e.message}"
        Rails.logger.warn "Failed to process IMAP for MailAccount##{account.id}: #{e.message}"
      end
    end
end
