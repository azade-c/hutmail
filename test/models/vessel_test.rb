require "test_helper"

class VesselTest < ActiveSupport::TestCase
  setup do
    @vessel = vessels(:one)
    @vessel.bundles.delete_all
  end

  # ------------------------------------------------------------------
  # Validations
  # ------------------------------------------------------------------

  test "requires a name, sailmail address and relay account" do
    vessel = Vessel.new

    assert_not vessel.valid?
    assert vessel.errors.added?(:name, :blank)
    assert vessel.errors.added?(:sailmail_address, :blank)
    assert vessel.errors.added?(:relay_account, :blank)
  end

  test "bundle_ratio must be a percentage and daily_budget_kb positive" do
    @vessel.bundle_ratio = 0
    @vessel.daily_budget_kb = 0

    assert_not @vessel.valid?
    assert @vessel.errors.of_kind?(:bundle_ratio, :in)
    assert @vessel.errors.of_kind?(:daily_budget_kb, :greater_than)
  end

  test "message_char_limit must be a positive integer when present" do
    @vessel.message_char_limit = 0
    assert_not @vessel.valid?
    assert @vessel.errors.of_kind?(:message_char_limit, :greater_than)

    @vessel.message_char_limit = nil
    assert @vessel.valid?
  end

  # ------------------------------------------------------------------
  # Radio budget (7 rolling days)
  # ------------------------------------------------------------------

  test "budget_consumed_7d sums only sent bundles within the rolling window" do
    sent_bundle(dispatch_size: 30_000, sent_at: 2.days.ago)
    sent_bundle(dispatch_size: 10_000, sent_at: 1.day.ago)
    sent_bundle(dispatch_size: 99_000, sent_at: 8.days.ago)
    @vessel.bundles.create!(status: "draft", dispatch_size: 50_000)

    assert_equal 40_000, @vessel.budget_consumed_7d
  end

  test "budget_remaining subtracts consumption from the weekly allowance" do
    @vessel.update!(daily_budget_kb: 100)
    sent_bundle(dispatch_size: 40_000, sent_at: 1.day.ago)

    weekly_allowance = 100 * 7 * 1024
    assert_equal weekly_allowance - 40_000, @vessel.budget_remaining
  end

  test "budget_remaining never goes negative" do
    @vessel.update!(daily_budget_kb: 1)
    sent_bundle(dispatch_size: 10_000_000, sent_at: 1.hour.ago)

    assert_equal 0, @vessel.budget_remaining
  end

  test "message and screener budgets split the remaining budget by ratio" do
    @vessel.update!(daily_budget_kb: 10, bundle_ratio: 80)
    remaining = @vessel.budget_remaining

    assert_in_delta remaining * 0.8, @vessel.message_budget, 0.001
    assert_in_delta remaining * 0.2, @vessel.screener_budget, 0.001
    assert_in_delta remaining, @vessel.message_budget + @vessel.screener_budget, 0.001
  end

  private
    def sent_bundle(dispatch_size:, sent_at:)
      @vessel.bundles.create!(status: "sent", dispatch_size:, sent_at:)
    end
end
