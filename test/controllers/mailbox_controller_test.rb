require "test_helper"

class MailboxesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "test@example.com", password: "password123")
    sign_in_as(@user)
  end

  test "should get show with no accounts" do
    get mailbox_url
    assert_response :success
    assert_match "No mail accounts", response.body
  end

  test "should require authentication" do
    sign_out
    get mailbox_url
    assert_redirected_to new_session_url
  end
end
