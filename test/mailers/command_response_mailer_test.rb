require "test_helper"

class CommandResponseMailerTest < ActionMailer::TestCase
  setup do
    @vessel = vessels(:one)
    @cr = @vessel.command_responses.create!(
      source: "subject",
      command: "PING",
      response_text: "PONG 2026-05-23T14:02Z hutmail",
      status: "pending"
    )
  end

  test "sets HUTMAIL <command> subject and response body" do
    mail = CommandResponseMailer.new.send_response(@cr)
    assert_equal "HUTMAIL PING", mail.subject
    assert_equal @vessel.sailmail_address, mail.to.first
    assert_includes mail.body.to_s, "PONG"
  end
end
