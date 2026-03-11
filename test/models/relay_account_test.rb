require "test_helper"

class RelayAccountTest < ActiveSupport::TestCase
  test "valid with all required fields" do
    account = relay_accounts(:one)
    assert account.valid?
  end

  test "requires server and credential fields" do
    account = RelayAccount.new(vessel: vessels(:one))
    assert_not account.valid?

    %i[imap_server imap_username imap_password
       smtp_server smtp_username smtp_password].each do |field|
      assert_includes account.errors[field], "can't be blank"
    end
  end

  test "auto-fills default ports from encryption" do
    account = RelayAccount.new(vessel: vessels(:one), imap_server: "imap.test.com", smtp_server: "smtp.test.com")
    account.valid?
    assert_equal 993, account.imap_port
    assert_equal 465, account.smtp_port
  end
end
