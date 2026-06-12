require "test_helper"

class VesselsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user_without_vessel = users(:no_vessel)
    @user_with_vessel = users(:one)
    @vessel = vessels(:one)
  end

  test "index lists user vessels" do
    sign_in_as @user_with_vessel
    get vessels_path
    assert_response :success
    assert_select "a[href='#{vessel_path(@vessel)}']"
  end

  test "index shows empty state for user without vessel" do
    sign_in_as @user_without_vessel
    get vessels_path
    assert_response :success
    assert_select ".empty-state"
  end

  test "show displays vessel detail" do
    sign_in_as @user_with_vessel
    get vessel_path(@vessel)
    assert_response :success
    assert_select "turbo-frame#dispatch-preview .btn__group"
    assert_select "turbo-frame#dispatch-preview form[action='#{vessel_dispatch_preview_path(@vessel)}'][data-turbo-frame='dispatch-preview']"
    assert_select "turbo-frame#dispatch-preview form[action='#{vessel_dispatch_path(@vessel)}'][data-turbo-frame='_top']" do
      assert_select "button:not([disabled])", text: "Envoyer maintenant"
    end
  end

  test "show keeps collect button visible and disables send when no messages are bundleable" do
    MessageDigest.where(
      mail_account_id: @vessel.mail_accounts.select(:id)
    ).update_all(status: MessageDigest.statuses.fetch("bundled"))

    sign_in_as @user_with_vessel
    get vessel_path(@vessel)

    assert_response :success
    assert_select "turbo-frame#dispatch-preview form[action='#{vessel_dispatch_preview_path(@vessel)}']" do
      assert_select "button", text: "Collecter & simuler"
    end
    assert_select "turbo-frame#dispatch-preview form[action='#{vessel_dispatch_path(@vessel)}']" do
      assert_select "button[disabled]", text: "Envoyer maintenant"
    end
  end

  test "show budget bar fill width reflects consumed percentage" do
    # daily_budget_kb 100 => total 100 * 7 * 1024 = 716_800 bytes.
    # A sent bundle of 358_400 bytes consumes exactly 50%.
    @vessel.bundles.create!(status: "sent", sent_at: Time.current, dispatch_size: 358_400)

    sign_in_as @user_with_vessel
    get vessel_path(@vessel)

    assert_response :success
    assert_select ".budget-bar__fill[style*='--budget-fill: 50.0%']"
  end

  test "show rejects access to unrelated vessel" do
    sign_in_as @user_without_vessel
    get vessel_path(@vessel)
    assert_redirected_to vessels_path
  end

  test "new shows form for user without vessel" do
    sign_in_as @user_without_vessel
    get new_vessel_path
    assert_response :success
    assert_select "form"
    assert_select "input[name='vessel[name]']"
    assert_select "input[name='vessel[relay_account_attributes][imap_server]']"
  end

  test "new shows form even if user already has a vessel" do
    sign_in_as @user_with_vessel
    get new_vessel_path
    assert_response :success
    assert_select "form"
  end

  test "create builds vessel with relay account and crew" do
    sign_in_as @user_without_vessel

    assert_difference [ "Vessel.count", "Crew.count", "RelayAccount.count" ], 1 do
      post vessels_path, params: { vessel: valid_vessel_params }
    end

    vessel = Vessel.find_by(name: "Test Vessel")
    assert_redirected_to vessel_path(vessel)
    assert vessel.relay_account
    assert_equal "imap.example.com", vessel.relay_account.imap_server
    assert_equal "captain", @user_without_vessel.crews.find_by(vessel:).role
  end

  test "create allows a second vessel for the same user" do
    sign_in_as @user_with_vessel

    assert_difference [ "Vessel.count", "Crew.count", "RelayAccount.count" ], 1 do
      post vessels_path, params: { vessel: valid_vessel_params(name: "Second Wind") }
    end

    vessel = Vessel.find_by(name: "Second Wind")
    assert_redirected_to vessel_path(vessel)
  end

  test "create rejects vessel without relay account" do
    sign_in_as @user_without_vessel

    assert_no_difference "Vessel.count" do
      post vessels_path, params: { vessel: { name: "No Relay", sailmail_address: "NR0001@sailmail.com" } }
    end

    assert_response :unprocessable_entity
  end

  test "create rejects vessel with incomplete relay account" do
    sign_in_as @user_without_vessel

    assert_no_difference "Vessel.count" do
      post vessels_path, params: {
        vessel: {
          name: "Incomplete", sailmail_address: "IC0001@sailmail.com",
          relay_account_attributes: { imap_server: "imap.example.com" }
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "create renders errors on invalid params" do
    sign_in_as @user_without_vessel

    assert_no_difference "Vessel.count" do
      post vessels_path, params: { vessel: { name: "" } }
    end

    assert_response :unprocessable_entity
  end

  private
    def sign_in_as(user)
      post session_path, params: { email_address: user.email_address, password: "password" }
    end

    def valid_vessel_params(overrides = {})
      {
        name: "Test Vessel",
        sailmail_address: "TV0001@sailmail.com",
        relay_account_attributes: {
          imap_server: "imap.example.com",
          imap_port: 993,
          imap_username: "relay@example.com",
          imap_password: "secret",
          smtp_server: "smtp.example.com",
          smtp_port: 587,
          smtp_username: "relay@example.com",
          smtp_password: "secret"
        }
      }.merge(overrides)
    end
end
