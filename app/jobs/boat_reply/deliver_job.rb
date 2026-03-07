class BoatReply::DeliverJob < ApplicationJob
  queue_as :default

  def perform(reply)
    OutboundMailer.send_reply(reply).deliver_now
    reply.update!(status: "sent", sent_at: Time.current)
  rescue => e
    reply.update!(status: "error", error_message: e.message)
    Rails.logger.error "BoatReply::DeliverJob##{reply.id} failed: #{e.message}"
  end
end
