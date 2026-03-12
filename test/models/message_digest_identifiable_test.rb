require "test_helper"

class MessageDigestIdentifiableTest < ActiveSupport::TestCase
  setup do
    @account = mail_accounts(:gmail)
  end

  test "auto-generates daily_sequence on create" do
    msg = @account.message_digests.create!(
      imap_uid: 300,
      imap_message_id: "autoid@example.com",
      from_address: "a@b.com",
      status: :collected,
      date: Date.new(2026, 3, 1),
      collected_at: Time.current,
      raw_size: 100,
      stripped_size: 50
    )

    assert_equal 2, msg.daily_sequence
    assert_equal "01mar.GM.2", msg.hutmail_reference
    assert_equal "01mar26.GM.2", msg.hutmail_reference(long: true)
  end

  test "generates sequential ids for same account and date" do
    date = Date.new(2026, 3, 7)
    msg1 = @account.message_digests.create!(
      imap_uid: 301, imap_message_id: "seq1@example.com",
      from_address: "a@b.com", status: :collected, date: date,
      collected_at: Time.current, raw_size: 100, stripped_size: 50
    )

    msg2 = @account.message_digests.create!(
      imap_uid: 302, imap_message_id: "seq2@example.com",
      from_address: "a@b.com", status: :collected, date: date,
      collected_at: Time.current, raw_size: 100, stripped_size: 50
    )

    assert_not_equal msg1.daily_sequence, msg2.daily_sequence
    assert_equal 2, msg2.daily_sequence
    assert_equal "07mar.GM.2", msg2.hutmail_reference
  end

  test "includes year suffix in short format when different from current year" do
    msg = @account.message_digests.create!(
      imap_uid: 303, imap_message_id: "year@example.com",
      from_address: "a@b.com", status: :collected, date: Date.new(2025, 1, 15),
      collected_at: Time.current, raw_size: 100, stripped_size: 50
    )

    assert_equal "15jan25.GM.1", msg.hutmail_reference
    assert_equal "15jan25.GM.1", msg.hutmail_reference(long: true)
  end

  test "decompose_hutmail_reference parses full reference" do
    result = MessageDigest.decompose_hutmail_reference("01mar.GM.1")
    assert_equal Date.new(Date.current.year, 3, 1), result[:date]
    assert_equal "GM", result[:short_code]
    assert_equal 1, result[:sequence]
  end

  test "decompose_hutmail_reference parses long reference" do
    result = MessageDigest.decompose_hutmail_reference("01mar25.GM.1")
    assert_equal Date.new(2025, 3, 1), result[:date]
    assert_equal "GM", result[:short_code]
    assert_equal 1, result[:sequence]
  end

  test "decompose_hutmail_reference parses date only" do
    result = MessageDigest.decompose_hutmail_reference("01mar")
    assert_equal Date.new(Date.current.year, 3, 1), result[:date]
    assert_nil result[:short_code]
    assert_nil result[:sequence]
  end
end
