require "test_helper"

class HutmailIdGeneratorTest < ActiveSupport::TestCase
  setup do
    @account = mail_accounts(:gmail)
  end

  test "generates id with zero-padded day and short code" do
    id = HutmailIdGenerator.generate(mail_account: @account, date: Date.new(2026, 3, 1))
    assert_match(/\A01mar\.GM\.\d+\z/, id)
  end

  test "generates sequential ids for same account and date" do
    date = Date.new(2026, 3, 7)
    id1 = HutmailIdGenerator.generate(mail_account: @account, date: date)
    # Simulate creating a message with this id
    @account.collected_messages.create!(
      hutmail_id: id1, imap_uid: 200, imap_message_id: "test1@example.com",
      from_address: "a@b.com", status: "pending", date: date, collected_at: Time.current
    )

    id2 = HutmailIdGenerator.generate(mail_account: @account, date: date)
    assert_not_equal id1, id2
    assert id2.end_with?(".2"), "Expected #{id2} to end with .2"
  end

  test "includes year suffix when different from current year" do
    id = HutmailIdGenerator.generate(mail_account: @account, date: Date.new(2025, 1, 15))
    assert_match(/\A15jan25\.GM\.\d+\z/, id)
  end

  test "parses full id" do
    result = HutmailIdGenerator.parse("01mar.GM.1")
    assert_equal Date.new(Date.current.year, 3, 1), result[:date]
    assert_equal "GM", result[:short_code]
    assert_equal 1, result[:sequence]
  end

  test "parses date only" do
    result = HutmailIdGenerator.parse("01mar")
    assert_equal Date.new(Date.current.year, 3, 1), result[:date]
    assert_nil result[:short_code]
    assert_nil result[:sequence]
  end

  test "parses mailbox code only" do
    result = HutmailIdGenerator.parse("GM")
    assert_nil result[:date]
    assert_equal "GM", result[:short_code]
    assert_nil result[:sequence]
  end

  test "parses sequence number only" do
    result = HutmailIdGenerator.parse("1")
    assert_nil result[:date]
    assert_nil result[:short_code]
    assert_equal 1, result[:sequence]
  end

  test "parses date with mailbox" do
    result = HutmailIdGenerator.parse("01mar.GM")
    assert_equal Date.new(Date.current.year, 3, 1), result[:date]
    assert_equal "GM", result[:short_code]
    assert_nil result[:sequence]
  end
end
