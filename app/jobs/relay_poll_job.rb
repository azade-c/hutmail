class RelayPollJob < ApplicationJob
  queue_as :default

  def perform
    Vessel.poll_all_now
  end
end
