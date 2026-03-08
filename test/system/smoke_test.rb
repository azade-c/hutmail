require "application_system_test_case"

class SmokeTest < ApplicationSystemTestCase
  test "loads sign in page" do
    visit new_session_path

    assert_current_path new_session_path
    assert_field "email_address"
    assert_field "password"
    assert_link "Forgot password?"
  end
end
