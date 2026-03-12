require "test_helper"

class MessageDigestTest < ActiveSupport::TestCase
  test "ordered scope sorts by id ascending" do
    account = mail_accounts(:gmail)
    account.message_digests.delete_all

    second = account.message_digests.create!(
      imap_uid: 300, imap_message_id: "second@test",
      from_address: "a@test", date: Time.parse("2026-03-01 20:44:00"),
      raw_size: 10, stripped_size: 5, status: "pending", collected_at: Time.current
    )
    first = account.message_digests.create!(
      imap_uid: 301, imap_message_id: "first@test",
      from_address: "b@test", date: Time.parse("2026-03-01 20:44:00"),
      raw_size: 10, stripped_size: 5, status: "pending", collected_at: Time.current
    )

    result = account.message_digests.ordered.pluck(:id)
    assert_equal [ second.id, first.id ], result
  end

  test "bundleable scope includes pending and resend" do
    account = mail_accounts(:gmail)
    account.message_digests.delete_all

    pending = account.message_digests.create!(
      imap_uid: 400, imap_message_id: "bundleable-pending@test",
      from_address: "a@test", date: Time.current,
      raw_size: 10, stripped_size: 5, status: "pending", collected_at: Time.current
    )
    resend = account.message_digests.create!(
      imap_uid: 401, imap_message_id: "bundleable-resend@test",
      from_address: "b@test", date: Time.current,
      raw_size: 10, stripped_size: 5, status: "resend", collected_at: Time.current
    )
    account.message_digests.create!(
      imap_uid: 402, imap_message_id: "bundleable-sent@test",
      from_address: "c@test", date: Time.current,
      raw_size: 10, stripped_size: 5, status: "sent", collected_at: Time.current
    )

    bundleable_ids = account.message_digests.bundleable.pluck(:id)
    assert_includes bundleable_ids, pending.id
    assert_includes bundleable_ids, resend.id
    assert_equal 2, bundleable_ids.size
  end

  test "status validation accepts resend" do
    account = mail_accounts(:gmail)
    msg = account.message_digests.build(
      imap_uid: 500, imap_message_id: "resend-valid@test",
      from_address: "a@test", date: Time.current,
      raw_size: 10, stripped_size: 5, status: "resend", collected_at: Time.current
    )
    assert msg.valid?, msg.errors.full_messages.inspect
  end
end
