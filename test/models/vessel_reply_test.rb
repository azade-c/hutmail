require "test_helper"

class VesselReplyTest < ActiveSupport::TestCase
  setup do
    @vessel = vessels(:one)
    @account = mail_accounts(:gmail)
  end

  test "deliver_now captures the outbound Message-ID" do
    reply = VesselReply.create!(
      vessel: @vessel, mail_account: @account, message_digest: nil,
      to_address: "alice@example.com", subject: "Hi", body: "hello", status: "pending"
    )

    outbound = Object.new
    outbound.define_singleton_method(:deliver_now) { true }
    outbound.define_singleton_method(:message_id) { "captured-reply-id@hutmail.example" }

    original_send_reply = OutboundMailer.method(:send_reply)
    OutboundMailer.define_singleton_method(:send_reply) do |_reply, **_opts|
      outbound
    end

    reply.deliver_now

    reply.reload
    assert_equal "sent", reply.status
    assert_equal "<captured-reply-id@hutmail.example>", reply.outbound_message_id,
      "outbound_message_id must be stored in bracketed canonical form to match IMAP envelopes"
  ensure
    OutboundMailer.define_singleton_method(:send_reply, original_send_reply)
  end

  test "deliver_now appends the sent copy to the account's Sent folder" do
    reply = VesselReply.create!(
      vessel: @vessel, mail_account: @account, message_digest: nil,
      to_address: "alice@example.com", subject: "Hi", body: "hello", status: "pending"
    )

    outbound = Object.new
    outbound.define_singleton_method(:deliver_now) { true }
    outbound.define_singleton_method(:message_id) { "reply-mid@hutmail.example" }
    outbound.define_singleton_method(:message) { Mail.new("Subject: Hi\n\nhello") }

    appended = []
    original_append = MailAccount.instance_method(:append_to_sent)
    MailAccount.define_method(:append_to_sent) do |raw|
      appended << raw
      "Sent"
    end

    original_send_reply = OutboundMailer.method(:send_reply)
    OutboundMailer.define_singleton_method(:send_reply) do |_reply, **_opts|
      outbound
    end

    reply.deliver_now

    assert_equal "sent", reply.reload.status
    assert_equal 1, appended.size, "Expected exactly one IMAP APPEND to Sent"
    assert_includes appended.first, "Subject: Hi"
  ensure
    OutboundMailer.define_singleton_method(:send_reply, original_send_reply)
    MailAccount.define_method(:append_to_sent, original_append)
  end

  test "deliver_now keeps status=sent even if appending to Sent folder fails" do
    reply = VesselReply.create!(
      vessel: @vessel, mail_account: @account, message_digest: nil,
      to_address: "alice@example.com", subject: "Hi", body: "hello", status: "pending"
    )

    outbound = Object.new
    outbound.define_singleton_method(:deliver_now) { true }
    outbound.define_singleton_method(:message_id) { nil }
    outbound.define_singleton_method(:message) { Mail.new("Subject: Hi\n\nhello") }

    original_append = MailAccount.instance_method(:append_to_sent)
    MailAccount.define_method(:append_to_sent) { |_raw| raise "no Sent folder writable" }

    original_send_reply = OutboundMailer.method(:send_reply)
    OutboundMailer.define_singleton_method(:send_reply) do |_reply, **_opts|
      outbound
    end

    reply.deliver_now

    assert_equal "sent", reply.reload.status, "APPEND failure must not roll back the SMTP success"
    assert_nil reply.error_message
  ensure
    OutboundMailer.define_singleton_method(:send_reply, original_send_reply)
    MailAccount.define_method(:append_to_sent, original_append)
  end

  test "deliver_now wraps an already-bracketed Message-ID without doubling brackets" do
    reply = VesselReply.create!(
      vessel: @vessel, mail_account: @account, message_digest: nil,
      to_address: "alice@example.com", subject: "Hi", body: "hello", status: "pending"
    )

    outbound = Object.new
    outbound.define_singleton_method(:deliver_now) { true }
    outbound.define_singleton_method(:message_id) { "<already-wrapped@hutmail.example>" }

    original_send_reply = OutboundMailer.method(:send_reply)
    OutboundMailer.define_singleton_method(:send_reply) do |_reply, **_opts|
      outbound
    end

    reply.deliver_now

    assert_equal "<already-wrapped@hutmail.example>", reply.reload.outbound_message_id
  ensure
    OutboundMailer.define_singleton_method(:send_reply, original_send_reply)
  end
end
