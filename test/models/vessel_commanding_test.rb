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

  test "MSG.<ACCOUNT> creates a fresh outbound message routed via that account" do
    text = "===MSG.GM bob@example.com===\nHello from the sea!\n===END==="
    results = @vessel.parse_and_execute_commands(text)

    result = results.first
    assert_equal "MSG.GM bob@example.com", result[:command]
    assert_equal :ok, result[:status]

    reply = @vessel.vessel_replies.order(:id).last
    assert_equal "bob@example.com", reply.to_address
    assert_equal mail_accounts(:gmail), reply.mail_account
    assert_nil reply.message_digest
    assert_equal "Hutmail message", reply.subject
  end

  test "MSG without account short_code returns an error" do
    text = "===MSG bob@example.com===\nbody\n===END==="
    assert_no_difference "@vessel.vessel_replies.count" do
      @results = @vessel.parse_and_execute_commands(text)
    end

    assert_equal :error, @results.first[:status]
    assert_match(/Invalid format/, @results.first[:message])
  end

  test "MSG.<UNKNOWN> returns an error" do
    text = "===MSG.XX bob@example.com===\nbody\n===END==="
    assert_no_difference "@vessel.vessel_replies.count" do
      @results = @vessel.parse_and_execute_commands(text)
    end

    assert_equal :error, @results.first[:status]
    assert_match(/Unknown account short_code: XX/, @results.first[:message])
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

  test "REPLY resolves MessageDigest by hutmail reference and threads correctly" do
    account = mail_accounts(:gmail)
    original = MessageDigest.create!(
      mail_account: account,
      from_address: "alice@example.com",
      subject: "Original subject",
      date: Date.new(2026, 5, 22),
      imap_message_id: "orig-789@example.com",
      imap_uid: 100,
      raw_size: 100, stripped_body: "hi", stripped_size: 2,
      daily_sequence: 3, status: "bundled",
      collected_at: Date.new(2026, 5, 22).beginning_of_day
    )

    text = "===REPLY 22may26.GM.3===\nQuick reply from the boat\n===END==="
    results = @vessel.parse_and_execute_commands(text)

    reply = @vessel.vessel_replies.order(:id).last
    assert_equal original, reply.message_digest
    assert_equal "alice@example.com", reply.to_address
    assert_equal "Re: Original subject", reply.subject
    assert_equal account, reply.mail_account
    assert_equal :ok, results.first[:status]
    assert_match(/alice@example.com/, results.first[:message])
  end

  test "REPLY with unknown hutmail_id reports error and creates no reply" do
    text = "===REPLY 99dec99.ZZ.999===\nbody\n===END==="
    before = @vessel.vessel_replies.count
    results = @vessel.parse_and_execute_commands(text)

    assert_equal before, @vessel.vessel_replies.count
    assert_equal :error, results.first[:status]
    assert_match(/Unknown hutmail_id/, results.first[:message])
  end

  test "REPLY and MSG can be mixed in the same payload" do
    account = mail_accounts(:gmail)
    original = MessageDigest.create!(
      mail_account: account,
      from_address: "alice@example.com",
      subject: "Topic A",
      date: Date.new(2026, 5, 22),
      imap_message_id: "a-1@example.com",
      imap_uid: 200,
      raw_size: 50, stripped_body: "hi", stripped_size: 2,
      daily_sequence: 1, status: "bundled",
      collected_at: Date.new(2026, 5, 22).beginning_of_day
    )

    text = <<~TEXT
      ===REPLY 22may26.GM.1===
      Reply to A
      ===MSG.OR bob@new.example===
      Spontaneous message via Orange
      ===END===
    TEXT
    @vessel.parse_and_execute_commands(text)

    replies = @vessel.vessel_replies.order(:id).last(2)
    reply = replies.find { |r| r.to_address == "alice@example.com" }
    msg   = replies.find { |r| r.to_address == "bob@new.example" }

    assert_equal original, reply.message_digest
    assert_equal "Re: Topic A", reply.subject
    assert_equal mail_accounts(:gmail), reply.mail_account

    assert_nil msg.message_digest
    assert_equal "Hutmail message", msg.subject
    assert_equal mail_accounts(:orange), msg.mail_account
  end

  test "REPLY does not double-prefix Re: when original subject already has it" do
    account = mail_accounts(:gmail)
    MessageDigest.create!(
      mail_account: account,
      from_address: "bob@example.com",
      subject: "Re: existing thread",
      date: Date.new(2026, 5, 22),
      imap_message_id: "thread-msg-456@example.com",
      imap_uid: 43,
      raw_size: 100, stripped_body: "hi", stripped_size: 2,
      daily_sequence: 7, status: "bundled",
      collected_at: Date.new(2026, 5, 22).beginning_of_day
    )

    text = "===REPLY 22may26.GM.7===\nReply body\n===END==="
    @vessel.parse_and_execute_commands(text)

    reply = @vessel.vessel_replies.order(:id).last
    assert_equal "Re: existing thread", reply.subject
  end

  test "SEND command requires account short_code" do
    text = "===CMD===\nSEND bob@example.com \"Hello\"\n===END==="
    assert_no_difference "@vessel.vessel_replies.count" do
      @results = @vessel.parse_and_execute_commands(text)
    end

    assert_equal :error, @results.first[:status]
    assert_match(/Invalid format/, @results.first[:message])
  end

  test "SEND.<ACCOUNT> dispatches message via the named account" do
    text = "===CMD===\nSEND.GM bob@example.com \"Quick note\"\n===END==="
    results = @vessel.parse_and_execute_commands(text)

    reply = @vessel.vessel_replies.order(:id).last
    assert_equal "bob@example.com", reply.to_address
    assert_equal mail_accounts(:gmail), reply.mail_account
    assert_equal "Quick note", reply.body
    assert_equal :ok, results.first[:status]
    assert_equal "SEND.GM bob@example.com", results.first[:command]
  end

  test "SEND.<UNKNOWN> returns error" do
    text = "===CMD===\nSEND.ZZ bob@example.com \"body\"\n===END==="
    assert_no_difference "@vessel.vessel_replies.count" do
      @results = @vessel.parse_and_execute_commands(text)
    end

    assert_equal :error, @results.first[:status]
    assert_match(/Unknown account short_code: ZZ/, @results.first[:message])
  end

  test "URGENT.<ACCOUNT> delivers immediately" do
    text = "===CMD===\nURGENT.GM bob@example.com \"NOW\"\n===END==="
    results = @vessel.parse_and_execute_commands(text)

    assert_equal :ok, results.first[:status]
    assert_equal "URGENT.GM bob@example.com", results.first[:command]
  end
end
