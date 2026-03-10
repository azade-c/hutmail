class VesselReply::DeliverJob < ApplicationJob
  queue_as :default

  def perform(reply)
    reply.deliver_now
  end
end
