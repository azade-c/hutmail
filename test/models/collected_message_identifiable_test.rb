require "test_helper"

class CollectedMessageIdentifiableTest < ActiveSupport::TestCase
  setup do
    @account = mail_accounts(:gmail)
  end

  test "auto-generates hutmail_id on create" do
    msg = @account.collected_messages.create!(
      imap_uid: 300,
      imap_message_id: "autoid@example.com",
      from_address: "a@b.com",
      status: "pending",
      date: Date.new(2026, 3, 1),
      collected_at: Time.current,
      raw_size: 100,
      stripped_size: 50
    )

    assert_match(/\A01mar\.GM\.\d+\z/, msg.hutmail_id)
  end

  test "generates sequential ids for same account and date" do
    date = Date.new(2026, 3, 7)
    msg1 = @account.collected_messages.create!(
      imap_uid: 301, imap_message_id: "seq1@example.com",
      from_address: "a@b.com", status: "pending", date: date,
      collected_at: Time.current, raw_size: 100, stripped_size: 50
    )

    msg2 = @account.collected_messages.create!(
      imap_uid: 302, imap_message_id: "seq2@example.com",
      from_address: "a@b.com", status: "pending", date: date,
      collected_at: Time.current, raw_size: 100, stripped_size: 50
    )

    assert_not_equal msg1.hutmail_id, msg2.hutmail_id
    assert msg2.hutmail_id.end_with?(".2"), "Expected #{msg2.hutmail_id} to end with .2"
  end

  test "includes year suffix when different from current year" do
    msg = @account.collected_messages.create!(
      imap_uid: 303, imap_message_id: "year@example.com",
      from_address: "a@b.com", status: "pending", date: Date.new(2025, 1, 15),
      collected_at: Time.current, raw_size: 100, stripped_size: 50
    )

    assert_match(/\A15jan25\.GM\.\d+\z/, msg.hutmail_id)
  end

  test "decompose_hutmail_id parses full id" do
    result = CollectedMessage.decompose_hutmail_id("01mar.GM.1")
    assert_equal Date.new(Date.current.year, 3, 1), result[:date]
    assert_equal "GM", result[:short_code]
    assert_equal 1, result[:sequence]
  end

  test "decompose_hutmail_id parses date only" do
    result = CollectedMessage.decompose_hutmail_id("01mar")
    assert_equal Date.new(Date.current.year, 3, 1), result[:date]
    assert_nil result[:short_code]
    assert_nil result[:sequence]
  end

  test "decompose_hutmail_id parses date with mailbox" do
    result = CollectedMessage.decompose_hutmail_id("01mar.GM")
    assert_equal Date.new(Date.current.year, 3, 1), result[:date]
    assert_equal "GM", result[:short_code]
    assert_nil result[:sequence]
  end
end
