module Bundle::Delivering
  extend ActiveSupport::Concern

  def deliver!
    RelayMailer.send_bundle(self).deliver_now
    record_as_sent!
  rescue => e
    update!(status: "error", error_message: e.message)
    Rails.logger.error "Bundle##{id} delivery failed: #{e.message}"
  end

  private
    def record_as_sent!
      now = Time.current
      update!(status: "sent", sent_at: now)
      collected_messages.update_all(status: "sent", sent_at: now)
      mark_sources_read
    end

    def mark_sources_read
      collected_messages.includes(:mail_account).group_by(&:mail_account).each do |account, msgs|
        account.mark_as_read(msgs.map(&:imap_uid))
      rescue => e
        Rails.logger.warn "Failed to mark IMAP read for MailAccount##{account.id}: #{e.message}"
      end
    end
end
