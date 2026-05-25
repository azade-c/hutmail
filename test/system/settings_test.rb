require "application_system_test_case"

class SettingsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @vessel = vessels(:one)
    @vessel.update!(dispatch_cadence: "manual")
  end

  test "user changes cadence from manual to every_hours and sees next_dispatch_at" do
    sign_in_via_form

    visit edit_vessel_settings_path(@vessel)
    assert_text "Programmation des dépêches"

    select "Toutes les N heures", from: "vessel[dispatch_cadence]"

    # Stimulus reveals the Intervalle field through a `change` handler.
    # Headless Chrome on Linux CI can race the show-then-type sequence on a
    # freshly-unhidden <input type=number> and silently drop the first
    # send_keys, so wait for the field to be interactable, use .set (clear +
    # set), and verify the value before submitting.
    hours_field = find_field("vessel[dispatch_every_hours]", visible: true, wait: 5)
    hours_field.set("3")
    assert_equal "3", hours_field.value, "every_hours field should hold the typed value before submit"

    select "UTC", from: "vessel[dispatch_timezone]"

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
