require "test_helper"

class VesselsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user_without_vessel = users(:no_vessel)
    @user_with_vessel = users(:one)
  end

  test "new shows form for user without vessel" do
    sign_in_as @user_without_vessel
    get new_vessel_path
    assert_response :success
    assert_select "form"
    assert_select "input[name='vessel[callsign]']"
  end

  test "new shows form even if user already has a vessel" do
    sign_in_as @user_with_vessel
    get new_vessel_path
    assert_response :success
    assert_select "form"
  end

  test "create builds vessel and crew" do
    sign_in_as @user_without_vessel

    assert_difference [ "Vessel.count", "Crew.count" ], 1 do
      post vessels_path, params: { vessel: { name: "Alibi II", callsign: "ZZ9999", sailmail_address: "ZZ9999@sailmail.com" } }
    end

    assert_redirected_to dashboard_path
    vessel = Vessel.find_by(callsign: "ZZ9999")
    assert vessel
    assert_equal "captain", @user_without_vessel.crews.find_by(vessel: vessel).role
  end

  test "create allows a second vessel for the same user" do
    sign_in_as @user_with_vessel

    assert_difference [ "Vessel.count", "Crew.count" ], 1 do
      post vessels_path, params: { vessel: { name: "Second Wind", callsign: "SW0001", sailmail_address: "SW0001@sailmail.com" } }
    end

    assert_redirected_to dashboard_path
  end

  test "create renders errors on invalid params" do
    sign_in_as @user_without_vessel

    assert_no_difference "Vessel.count" do
      post vessels_path, params: { vessel: { name: "No Callsign" } }
    end

    assert_response :unprocessable_entity
  end

  private
    def sign_in_as(user)
      post session_path, params: { email_address: user.email_address, password: "password" }
    end
end
