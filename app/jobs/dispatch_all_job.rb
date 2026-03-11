class DispatchAllJob < ApplicationJob
  queue_as :default

  def perform
    Vessel.dispatch_all_now
  end
end
