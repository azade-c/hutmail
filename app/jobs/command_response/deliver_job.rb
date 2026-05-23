class CommandResponse::DeliverJob < ApplicationJob
  queue_as :default

  def perform(command_response)
    command_response.deliver_now
  end
end
