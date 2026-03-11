class CycleAllJob < ApplicationJob
  queue_as :default

  def perform
    Vessel.cycle_all_now
  end
end
