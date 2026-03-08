class BundleAllJob < ApplicationJob
  queue_as :default

  def perform
    Vessel.find_each do |vessel|
      builder = BundleBuilder.new(vessel)
      builder.build_and_deliver
    rescue => e
      Rails.logger.error "BundleAllJob: Vessel##{vessel.id} failed: #{e.message}"
    end
  end
end
