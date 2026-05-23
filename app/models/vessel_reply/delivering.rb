module VesselReply::Delivering
  extend ActiveSupport::Concern

  def deliver_later
    VesselReply::DeliverJob.perform_later(self)
  end

  def deliver_now
    account = mail_account

    message = OutboundMailer.new.deliver_with_auth_fallback(account) do |auth_method|
      OutboundMailer.send_reply(self, auth_method:)
    end

    attrs = { status: "sent", sent_at: Time.current }
    attrs[:outbound_message_id] = message.message_id if message&.message_id.present?
    update!(attrs)
  rescue => e
    update!(status: "error", error_message: e.message)
    Rails.logger.error "VesselReply##{id} delivery failed: #{e.message}"
  end
end
