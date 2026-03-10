require "test_helper"

class RelayAccountTest < ActiveSupport::TestCase
  test "valid with all required fields" do
    account = relay_accounts(:one)
    assert account.valid?
  end

  test "requires imap and smtp server fields" do
    account = RelayAccount.new(vessel: vessels(:one))
    assert_not account.valid?

    %i[imap_server imap_port imap_username imap_password
       smtp_server smtp_port smtp_username smtp_password].each do |field|
      assert_includes account.errors[field], "can't be blank"
    end
  end
end
