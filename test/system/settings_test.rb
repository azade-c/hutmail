require "application_system_test_case"

class SettingsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @vessel = vessels(:one)
    # Pre-populate dispatch_every_hours alongside cadence=manual: the
    # validation is conditional on cadence==every_hours, so the integer just
    # sits in the column until the user flips cadence. This lets the test
    # exercise the user flow ("change cadence -> see next dispatch") without
    # depending on Capybara typing into a number input that Stimulus has just
    # un-hidden -- a sequence that headless Chrome on Linux CI silently
    # drops keystrokes for.
    @vessel.update!(
      dispatch_cadence: "manual",
      dispatch_every_hours: 3,
      dispatch_timezone: "UTC"
    )
  end

  test "user changes cadence from manual to every_hours and sees next_dispatch_at" do
    sign_in_via_form

    visit edit_vessel_settings_path(@vessel)
    assert_text "Programmation des dépêches"
    # Manual cadence does not surface a next-dispatch line yet.
    assert_no_text "Prochaine dépêche prévue"

    select "Toutes les N heures", from: "vessel[dispatch_cadence]"
    click_button "Enregistrer"

    assert_text "Réglages enregistrés.", wait: 5
    assert_text "Prochaine dépêche prévue"

    @vessel.reload
    assert_equal "every_hours", @vessel.dispatch_cadence
    assert_equal 3, @vessel.dispatch_every_hours
    assert_not_nil @vessel.next_dispatch_at
    assert @vessel.next_dispatch_at > Time.current
    assert @vessel.next_dispatch_at <= 3.hours.from_now + 1.minute
  end

  private
    def sign_in_via_form
      visit new_session_path
      fill_in "email_address", with: @user.email_address
      fill_in "password",      with: "password"
      click_button "Se connecter"
      # Wait for redirect away from the login page before the test continues.
      assert_no_current_path new_session_path, wait: 5
    end
end
