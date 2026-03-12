require "test_helper"

class CollectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @account = mail_accounts(:gmail)
    sign_in_as @user
  end

  test "create reruns collection and redirects" do
    original = MailAccount.instance_method(:collect_now)
    collect_now_called = false
    MailAccount.define_method(:collect_now) do
      collect_now_called = true
      0
    end

    post mail_account_collection_path(@account)

    assert_redirected_to mail_account_path(@account)
    assert_equal "Collecte relancée.", flash[:notice]
    assert collect_now_called
  ensure
    MailAccount.define_method(:collect_now, original)
  end

  test "create rejects access from unrelated user" do
    sign_in_as users(:no_vessel)
    post mail_account_collection_path(@account)
    assert_redirected_to vessels_path
  end

  private
    def sign_in_as(user)
      post session_path, params: { email_address: user.email_address, password: "password" }
    end
end
