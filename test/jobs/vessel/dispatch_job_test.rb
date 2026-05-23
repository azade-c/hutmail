require "test_helper"

class Vessel::DispatchJobTest < ActiveJob::TestCase
  setup do
    @vessel = vessels(:one)
    @vessel.update!(
      dispatch_cadence: "every_hours",
      dispatch_every_hours: 2
    )
  end

  test "calls collect_all_accounts and dispatch_now, then reschedules" do
    calls = []
    @vessel.define_singleton_method(:collect_all_accounts) { calls << :collect }
    @vessel.define_singleton_method(:dispatch_now) { calls << :dispatch; nil }

    travel_to Time.utc(2026, 5, 23, 12, 0, 0) do
      Vessel::DispatchJob.perform_now(@vessel)
    end

    assert_equal %i[collect dispatch], calls
    @vessel.reload
    assert_in_delta Time.utc(2026, 5, 23, 12, 0, 0).to_i, @vessel.last_dispatched_at.to_i, 5
    assert_in_delta Time.utc(2026, 5, 23, 14, 0, 0).to_i, @vessel.next_dispatch_at.to_i, 5
  end

  test "reschedules even when dispatch raises" do
    @vessel.define_singleton_method(:collect_all_accounts) { }
    @vessel.define_singleton_method(:dispatch_now) { raise "boom" }

    travel_to Time.utc(2026, 5, 23, 12, 0, 0) do
      assert_raises(RuntimeError) { Vessel::DispatchJob.perform_now(@vessel) }
    end

    @vessel.reload
    assert_not_nil @vessel.last_dispatched_at
    assert_not_nil @vessel.next_dispatch_at
  end
end
