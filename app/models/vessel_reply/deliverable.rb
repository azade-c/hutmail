module VesselReply::Deliverable
  extend ActiveSupport::Concern

  def deliver_later
    VesselReply::DeliverJob.perform_later(self)
  end

  def deliver_now
    OutboundMailer.send_reply(self).deliver_now
    update!(status: "sent", sent_at: Time.current)
  rescue => e
    update!(status: "error", error_message: e.message)
    Rails.logger.error "VesselReply##{id} delivery failed: #{e.message}"
  end
end
