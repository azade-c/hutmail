require "test_helper"

class MailAccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @mail_account = mail_accounts(:gmail)
    @mail_account.message_digests.delete_all
  end

  test "show lists collected messages with the most recent first" do
    older = create_digest(seq: 1, uid: 10, subject: "Oldest")
    newer = create_digest(seq: 2, uid: 20, subject: "Newest")

    sign_in_as @user
    get mail_account_path(@mail_account)
    assert_response :success

    body = response.body
    assert_operator body.index(newer.hutmail_reference), :<, body.index(older.hutmail_reference),
      "Expected the most recent message to appear before the oldest in the view"
  end

  test "show does not change the underlying :ordered scope" do
    create_digest(seq: 1, uid: 10, subject: "A")
    create_digest(seq: 2, uid: 20, subject: "B")

    scoped = @mail_account.message_digests.ordered.to_a
    assert_equal scoped.sort_by(&:imap_uid).map(&:id), scoped.map(&:id),
      ":ordered must still return messages oldest-first (ascending imap_uid)"
  end

  private
    def create_digest(seq:, uid:, subject:)
      @mail_account.message_digests.create!(
        from_address: "sender#{uid}@example.com",
        subject: subject,
        date: Date.new(2026, 3, 1).beginning_of_day + uid.minutes,
        imap_message_id: "msg-#{uid}@example.com",
        imap_uid: uid,
        raw_size: 100, stripped_body: "hi", stripped_size: 2,
        daily_sequence: seq, status: "collected",
        collected_at: Date.new(2026, 3, 1).beginning_of_day
      )
    end
end
