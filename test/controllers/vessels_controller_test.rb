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
