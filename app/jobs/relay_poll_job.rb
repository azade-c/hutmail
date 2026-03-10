class RelayPollJob < ApplicationJob
  queue_as :default

  def perform
    Vessel.find_each do |vessel|
      vessel.poll_relay_now
    rescue => e
      Rails.logger.error "RelayPollJob: Vessel##{vessel.id} failed: #{e.message}"
    end
  end
end
