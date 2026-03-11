require "test_helper"

class ConnectionFieldsPagesTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @vessel = vessels(:one)
    sign_in_as @user
  end

  test "settings edit page renders" do
    get edit_vessel_settings_path(@vessel)
    assert_response :success
  end

  test "new mail account page renders" do
    get new_vessel_mail_account_path(@vessel)
    assert_response :success
  end

  test "edit mail account page renders" do
    mail_account = mail_accounts(:gmail)
    get edit_vessel_mail_account_path(@vessel, mail_account)
    assert_response :success
  end
end
