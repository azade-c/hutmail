class DispatchDueVesselsJob < ApplicationJob
  queue_as :default

  def perform
    Vessel.due_for_dispatch.find_each do |vessel|
      Vessel::DispatchJob.perform_later(vessel)
    end
  end
end
