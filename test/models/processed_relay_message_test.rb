require "test_helper"

class ProcessedRelayMessageTest < ActiveSupport::TestCase
  test "valid with vessel and message id" do
    msg = ProcessedRelayMessage.new(vessel: vessels(:one), imap_message_id: "test@sailmail.com")
    assert msg.valid?
  end

  test "requires imap_message_id" do
    msg = ProcessedRelayMessage.new(vessel: vessels(:one))
    assert_not msg.valid?
    assert_includes msg.errors[:imap_message_id], "can't be blank"
  end

  test "enforces uniqueness per vessel" do
    ProcessedRelayMessage.create!(vessel: vessels(:one), imap_message_id: "dupe@sailmail.com")

    duplicate = ProcessedRelayMessage.new(vessel: vessels(:one), imap_message_id: "dupe@sailmail.com")
    assert_not duplicate.valid?
  end
end
