class BundleAllJob < ApplicationJob
  queue_as :default

  def perform
    Vessel.bundle_all_now
  end
end
