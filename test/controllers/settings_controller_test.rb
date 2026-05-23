require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @vessel = vessels(:one)
    sign_in_as @user
  end

  test "edit renders the schedule card" do
    get edit_vessel_settings_path(@vessel)
    assert_response :success
    assert_select "select[name='vessel[dispatch_cadence]']"
    assert_select "input[name='vessel[dispatch_every_hours]']"
    assert_select "input[name='vessel[dispatch_daily_at]']"
    assert_select "select[name='vessel[dispatch_timezone]']"
  end

  test "update persists schedule and recomputes next_dispatch_at" do
    travel_to Time.utc(2026, 5, 23, 12, 0, 0) do
      patch vessel_settings_path(@vessel), params: {
        vessel: {
          dispatch_cadence: "every_hours",
          dispatch_every_hours: 4,
          dispatch_timezone: "UTC"
        }
      }
      assert_redirected_to edit_vessel_settings_path(@vessel)
      @vessel.reload
      assert_equal "every_hours", @vessel.dispatch_cadence
      assert_equal 4, @vessel.dispatch_every_hours
      assert_equal Time.utc(2026, 5, 23, 16, 0, 0), @vessel.next_dispatch_at
    end
  end

  test "update rejects invalid cadence" do
    patch vessel_settings_path(@vessel), params: {
      vessel: { dispatch_cadence: "weekly" }
    }
    assert_response :unprocessable_entity
  end
end
