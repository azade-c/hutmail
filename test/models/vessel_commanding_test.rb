require "test_helper"

class VesselCommandingTest < ActiveSupport::TestCase
  setup do
    @vessel = vessels(:one)
  end

  test "parses STATUS command" do
    text = "===CMD===\nSTATUS\n===END==="
    results = @vessel.parse_and_execute_commands(text)

    assert_equal 1, results.size
    assert_equal "STATUS", results.first[:command]
    assert_equal :ok, results.first[:status]
    assert_includes results.first[:message], "ready for bundling"
  end

  test "parses MSG blocks" do
    text = "===MSG bob@example.com===\nHello from the sea!\n===END==="
    results = @vessel.parse_and_execute_commands(text)

    result = results.first
    assert_equal "MSG bob@example.com", result[:command]
    assert_equal :ok, result[:status]
  end

  test "ignores comments in commands" do
    text = "===CMD===\n# This is a comment\nSTATUS\n===END==="
    results = @vessel.parse_and_execute_commands(text)

    assert_equal 1, results.size
    assert_equal "STATUS", results.first[:command]
  end

  test "handles multiple commands" do
    text = "===CMD===\nSTATUS\nPAUSE 3d\n===END==="
    results = @vessel.parse_and_execute_commands(text)

    assert_equal 2, results.size
  end

  test "handles unknown commands" do
    text = "===CMD===\nDROP 01mar.GM.1\n===END==="
    results = @vessel.parse_and_execute_commands(text)

    assert_equal :unknown, results.first[:status]
  end

  test "MSG block links vessel_reply to the original MessageDigest for threading" do
    account = mail_accounts(:gmail)
    original = MessageDigest.create!(
      mail_account: account,
      from_address: "alice@example.com",
      subject: "Hello from shore",
      date: 1.day.ago,
      imap_message_id: "orig-msg-123@example.com",
      imap_uid: 42,
      raw_size: 100,
      stripped_body: "hi",
      stripped_size: 2,
      daily_sequence: 1,
      status: "bundled",
      collected_at: 1.day.ago
    )

    text = "===MSG alice@example.com===\nGreetings from the sea\n===END==="
    @vessel.parse_and_execute_commands(text)

    reply = @vessel.vessel_replies.order(:id).last
    assert_equal original, reply.message_digest
    assert_equal "Re: Hello from shore", reply.subject
  end

  test "MSG block to unknown recipient uses default account and HutMail reply subject" do
    text = "===MSG newperson@example.com===\nBody\n===END==="
    @vessel.parse_and_execute_commands(text)

    reply = @vessel.vessel_replies.order(:id).last
    assert_nil reply.message_digest
    assert_equal "HutMail reply", reply.subject
  end

  test "does not double-prefix Re: when original subject already has it" do
    account = mail_accounts(:gmail)
    MessageDigest.create!(
      mail_account: account,
      from_address: "bob@example.com",
      subject: "Re: existing thread",
      date: 1.day.ago,
      imap_message_id: "thread-msg-456@example.com",
      imap_uid: 43,
      raw_size: 100,
      stripped_body: "hi",
      stripped_size: 2,
      daily_sequence: 1,
      status: "bundled",
      collected_at: 1.day.ago
    )

    text = "===MSG bob@example.com===\nReply body\n===END==="
    @vessel.parse_and_execute_commands(text)

    reply = @vessel.vessel_replies.order(:id).last
    assert_equal "Re: existing thread", reply.subject
  end
end
