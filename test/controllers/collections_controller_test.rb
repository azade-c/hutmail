require "test_helper"

class CollectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @account = mail_accounts(:gmail)
    sign_in_as @user
  end

  test "create clears pending and redirects" do
    @account.collected_messages.create!(
      imap_uid: 800, imap_message_id: "stale@test",
      from_address: "x@test", status: "pending",
      date: Time.current, collected_at: Time.current,
      raw_size: 10, stripped_body: "stale", stripped_size: 5
    )

    original = MailAccount.instance_method(:collect_now)
    MailAccount.define_method(:collect_now) { 0 }

    post mail_account_collection_path(@account)

    assert_redirected_to mail_account_path(@account)
    assert_equal "Collecte relancée.", flash[:notice]
    assert_not @account.collected_messages.pending.exists?(imap_message_id: "stale@test")
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
