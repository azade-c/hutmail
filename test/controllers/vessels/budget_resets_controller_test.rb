require "test_helper"

class Vessels::BudgetResetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @vessel = vessels(:one)
    sign_in_as @user
  end

  test "create resets the rolling budget and redirects to the vessel" do
    @vessel.update!(daily_budget_kb: 100)
    @vessel.bundles.create!(
      status: "sent",
      sent_at: 1.day.ago,
      messages_count: 1,
      dispatch_size: 50_000
    )
    assert_equal 50_000, @vessel.budget_consumed_7d

    post vessel_budget_reset_path(@vessel)

    assert_redirected_to vessel_path(@vessel)
    assert_match(/Budget remis à zéro/, flash[:notice])
    assert_equal 0, @vessel.reload.budget_consumed_7d
  end

  test "create rejects access from unrelated user" do
    sign_in_as users(:no_vessel)
    post vessel_budget_reset_path(@vessel)
    assert_redirected_to vessels_path
  end

  private
    def sign_in_as(user)
      post session_path, params: { email_address: user.email_address, password: "password" }
    end
end
