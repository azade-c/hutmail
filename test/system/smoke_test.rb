require "application_system_test_case"

class SmokeTest < ApplicationSystemTestCase
  test "loads sign in page" do
    visit new_session_path
    assert_text "Sign in"
  end
end
