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

  # ------------------------------------------------------------------
  # The tracking link
  # ------------------------------------------------------------------

  test "edit offers the tracking link for editing" do
    get edit_vessel_settings_path(@vessel)

    assert_response :success
    assert_select "input[name='vessel[track_slug]'][value=?]", @vessel.track_slug
  end

  test "the skipper can choose a readable tracking link" do
    patch vessel_settings_path(@vessel), params: {
      vessel: { track_slug: "AlibiEnRouteVersLeSud" }
    }

    assert_redirected_to edit_vessel_settings_path(@vessel)
    assert_equal "AlibiEnRouteVersLeSud", @vessel.reload.track_slug

    get track_path("AlibiEnRouteVersLeSud")
    assert_response :success
  end

  test "changing the link retires the old one on the spot" do
    was = @vessel.track_slug

    patch vessel_settings_path(@vessel), params: {
      vessel: { track_slug: "AlibiEnRouteVersLeSud" }
    }

    get "/suivi/#{was}"
    assert_response :not_found
  end

  test "clearing the link is how a leaked URL gets revoked" do
    was = @vessel.track_slug

    patch vessel_settings_path(@vessel), params: { vessel: { track_slug: "" } }

    assert_redirected_to edit_vessel_settings_path(@vessel)
    assert_not_equal was, @vessel.reload.track_slug

    get "/suivi/#{was}"
    assert_response :not_found
  end

  # A link that fails the route constraint would 404 for the family, so it has
  # to be refused at the form rather than saved and quietly broken.
  test "a guessable link is refused in French and nothing is saved" do
    was = @vessel.track_slug

    patch vessel_settings_path(@vessel), params: { vessel: { track_slug: "trop-court" } }

    assert_response :unprocessable_entity
    assert_equal was, @vessel.reload.track_slug
    assert_match "Lien de suivi doit faire de 16 à 64 lettres ou chiffres", response.body
  end

  # The form prints the live URL, and url_for enforces the route constraint. If
  # it ever read the slug being typed instead of the saved one, this 500s.
  test "the form still renders when the submitted link is invalid" do
    patch vessel_settings_path(@vessel), params: { vessel: { track_slug: "nope" } }

    assert_response :unprocessable_entity
    assert_match track_url(@vessel.track_slug), response.body
  end
end
