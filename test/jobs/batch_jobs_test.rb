require "test_helper"

class BatchJobsTest < ActiveJob::TestCase
  test "CollectAllJob delegates to MailAccount.collect_all_now" do
    assert_delegates(MailAccount, :collect_all_now) { CollectAllJob.perform_now }
  end

  test "CycleAllJob delegates to Vessel.cycle_all_now" do
    assert_delegates(Vessel, :cycle_all_now) { CycleAllJob.perform_now }
  end

  test "DispatchAllJob delegates to Vessel.dispatch_all_now" do
    assert_delegates(Vessel, :dispatch_all_now) { DispatchAllJob.perform_now }
  end

  test "RelayPollJob delegates to Vessel.poll_all_now" do
    assert_delegates(Vessel, :poll_all_now) { RelayPollJob.perform_now }
  end

  private
    def assert_delegates(klass, method)
      called = 0
      original = klass.method(method)
      klass.define_singleton_method(method) { called += 1 }
      yield
      assert_equal 1, called, "expected #{klass}.#{method} to be called once"
    ensure
      klass.define_singleton_method(method, original)
    end
end
