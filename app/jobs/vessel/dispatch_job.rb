class Vessel::DispatchJob < ApplicationJob
  queue_as :default

  def perform(vessel)
    vessel.collect_all_accounts
    vessel.dispatch_now
  ensure
    now = Time.current
    vessel.last_dispatched_at = now
    vessel.update_columns(
      last_dispatched_at: now,
      next_dispatch_at: vessel.compute_next_dispatch_at
    )
  end
end
