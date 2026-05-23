require "test_helper"

class VesselSchedulingTest < ActiveSupport::TestCase
  setup do
    @vessel = vessels(:one)
  end

  test "manual cadence yields nil next_dispatch_at" do
    @vessel.update!(dispatch_cadence: "manual")
    assert_nil @vessel.next_dispatch_at
  end

  test "every_hours cadence computes next from last_dispatched_at" do
    travel_to Time.utc(2026, 5, 23, 12, 0, 0) do
      @vessel.update!(
        dispatch_cadence: "every_hours",
        dispatch_every_hours: 3,
        last_dispatched_at: Time.utc(2026, 5, 23, 10, 0, 0)
      )
      assert_equal Time.utc(2026, 5, 23, 13, 0, 0), @vessel.next_dispatch_at
    end
  end

  test "every_hours falls back to now when last_dispatched_at nil" do
    travel_to Time.utc(2026, 5, 23, 12, 0, 0) do
      @vessel.update!(
        dispatch_cadence: "every_hours",
        dispatch_every_hours: 6
      )
      assert_equal Time.utc(2026, 5, 23, 18, 0, 0), @vessel.next_dispatch_at
    end
  end

  test "daily cadence picks today when time is in the future" do
    travel_to Time.utc(2026, 5, 23, 6, 0, 0) do
      @vessel.update!(
        dispatch_cadence: "daily",
        dispatch_daily_at: "09:30",
        dispatch_timezone: "UTC"
      )
      assert_equal Time.utc(2026, 5, 23, 9, 30, 0), @vessel.next_dispatch_at
    end
  end

  test "daily cadence rolls over to tomorrow when time has passed" do
    travel_to Time.utc(2026, 5, 23, 10, 0, 0) do
      @vessel.update!(
        dispatch_cadence: "daily",
        dispatch_daily_at: "09:30",
        dispatch_timezone: "UTC"
      )
      assert_equal Time.utc(2026, 5, 24, 9, 30, 0), @vessel.next_dispatch_at
    end
  end

  test "daily cadence respects dispatch_timezone" do
    travel_to Time.utc(2026, 5, 23, 6, 0, 0) do
      @vessel.update!(
        dispatch_cadence: "daily",
        dispatch_daily_at: "09:00",
        dispatch_timezone: "Europe/Paris"
      )
      assert_equal Time.utc(2026, 5, 23, 7, 0, 0), @vessel.next_dispatch_at
    end
  end

  test "rejects invalid cadence" do
    @vessel.dispatch_cadence = "weekly"
    assert_not @vessel.valid?
    assert_includes @vessel.errors[:dispatch_cadence], "is not included in the list"
  end

  test "rejects out-of-range every_hours" do
    @vessel.dispatch_cadence = "every_hours"
    @vessel.dispatch_every_hours = 0
    assert_not @vessel.valid?
  end

  test "rejects malformed dispatch_daily_at" do
    @vessel.dispatch_cadence = "daily"
    @vessel.dispatch_daily_at = "9:5"
    assert_not @vessel.valid?
  end

  test "rejects unknown timezone" do
    @vessel.dispatch_timezone = "Mars/Olympus"
    assert_not @vessel.valid?
  end

  test "due_for_dispatch scope returns only past-due vessels" do
    travel_to Time.utc(2026, 5, 23, 12, 0, 0) do
      Vessel.update_all(next_dispatch_at: nil)
      @vessel.update_columns(next_dispatch_at: 1.hour.ago)
      assert_includes Vessel.due_for_dispatch, @vessel

      @vessel.update_columns(next_dispatch_at: 1.hour.from_now)
      assert_not_includes Vessel.due_for_dispatch, @vessel
    end
  end
end
