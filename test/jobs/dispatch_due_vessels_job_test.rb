require "test_helper"

class DispatchDueVesselsJobTest < ActiveJob::TestCase
  setup do
    @vessel = vessels(:one)
  end

  test "enqueues Vessel::DispatchJob for due vessels only" do
    @vessel.update_columns(next_dispatch_at: 5.minutes.ago)

    assert_enqueued_with(job: Vessel::DispatchJob, args: [ @vessel ]) do
      DispatchDueVesselsJob.perform_now
    end
  end

  test "does not enqueue when no vessel is due" do
    @vessel.update_columns(next_dispatch_at: nil)

    assert_no_enqueued_jobs only: Vessel::DispatchJob do
      DispatchDueVesselsJob.perform_now
    end
  end

  test "does not enqueue for future schedules" do
    @vessel.update_columns(next_dispatch_at: 1.hour.from_now)

    assert_no_enqueued_jobs only: Vessel::DispatchJob do
      DispatchDueVesselsJob.perform_now
    end
  end
end
