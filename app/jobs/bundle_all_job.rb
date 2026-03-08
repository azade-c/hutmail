class BundleAllJob < ApplicationJob
  queue_as :default

  def perform
    Vessel.find_each do |vessel|
      vessel.build_and_deliver_bundle
    rescue => e
      Rails.logger.error "BundleAllJob: Vessel##{vessel.id} failed: #{e.message}"
    end
  end
end
