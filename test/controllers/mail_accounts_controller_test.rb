require "test_helper"

class MailAccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "test@example.com", password: "password123")
    sign_in_as(@user)
  end

  test "should get index" do
    get mail_accounts_url
    assert_response :success
  end

  test "should get new" do
    get new_mail_account_url
    assert_response :success
  end

  test "should require authentication" do
    sign_out
    get mail_accounts_url
    assert_redirected_to new_session_url
  end
end
