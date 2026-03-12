module Bundle::Delivering
  extend ActiveSupport::Concern

  def deliver!
    RelayMailer.send_bundle(self).deliver_now
    record_as_sent!
    mark_sources_processed
  rescue => e
    if sent?
      Rails.logger.warn "Bundle##{id} sent but IMAP processing failed: #{e.message}"
    else
      update!(status: "error", error_message: e.message)
      Rails.logger.error "Bundle##{id} delivery failed: #{e.message}"
    end
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
        account.mark_as_processed(msgs.map(&:imap_uid))
      rescue => e
        Rails.logger.warn "Failed to process IMAP for MailAccount##{account.id}: #{e.message}"
      end
    end
end
