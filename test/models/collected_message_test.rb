require "test_helper"

class CollectedMessageTest < ActiveSupport::TestCase
  test "ordered scope sorts by id ascending" do
    account = mail_accounts(:gmail)
    account.collected_messages.delete_all

    second = account.collected_messages.create!(
      imap_uid: 300, imap_message_id: "second@test",
      from_address: "a@test", date: Time.parse("2026-03-01 20:44:00"),
      raw_size: 10, stripped_size: 5, status: "pending", collected_at: Time.current
    )
    first = account.collected_messages.create!(
      imap_uid: 301, imap_message_id: "first@test",
      from_address: "b@test", date: Time.parse("2026-03-01 20:44:00"),
      raw_size: 10, stripped_size: 5, status: "pending", collected_at: Time.current
    )

    result = account.collected_messages.ordered.pluck(:id)
    assert_equal [ second.id, first.id ], result
  end
end
