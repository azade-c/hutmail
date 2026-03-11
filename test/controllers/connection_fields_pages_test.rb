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
    get edit_vessel_mail_account_path(@vessel, mail_accounts(:gmail))
    assert_response :success
  end

  test "create mail account succeeds" do
    assert_difference "MailAccount.count", 1 do
      post vessel_mail_accounts_path(@vessel), params: {
        mail_account: {
          name: "Proton", short_code: "PR",
          imap_server: "imap.proton.me", imap_port: 993, imap_encryption: "ssl",
          imap_username: "test@proton.me", imap_password: "secret",
          smtp_server: "smtp.proton.me", smtp_port: 465, smtp_encryption: "ssl",
          smtp_username: "test@proton.me", smtp_password: "secret"
        }
      }
    end
    assert_redirected_to vessel_mail_account_path(@vessel, MailAccount.last)
  end

  test "create mail account renders errors on invalid params" do
    assert_no_difference "MailAccount.count" do
      post vessel_mail_accounts_path(@vessel), params: {
        mail_account: { name: "", short_code: "" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "update settings succeeds" do
    patch vessel_settings_path(@vessel), params: {
      vessel: { name: "Renamed Boat" }
    }
    assert_redirected_to edit_vessel_settings_path(@vessel)
    assert_equal "Renamed Boat", @vessel.reload.name
  end

  test "show mail account page renders" do
    get vessel_mail_account_path(@vessel, mail_accounts(:gmail))
    assert_response :success
  end

  test "mail accounts index page renders" do
    get vessel_mail_accounts_path(@vessel)
    assert_response :success
  end

  test "bundles index page renders" do
    get vessel_bundles_path(@vessel)
    assert_response :success
  end
end
