require "test_helper"

class CollectedMessagePresentableTest < ActiveSupport::TestCase
  setup do
    @account = mail_accounts(:gmail)
  end

  test "to_screener_line formats compactly" do
    msg = @account.collected_messages.create!(
      imap_uid: 100,
      imap_message_id: "screener-presentable@example.com",
      from_address: "bob@example.com",
      from_name: "Bob",
      subject: "Hello from land",
      date: Time.current,
      raw_size: 2000,
      stripped_body: "Hello!",
      stripped_size: 6,
      status: "pending",
      collected_at: Time.current
    )

    line = msg.to_screener_line
    assert_includes line, msg.hutmail_id
    assert_includes line, "Bob"
    assert_includes line, "Hello from land"
  end
end
