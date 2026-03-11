require "test_helper"
require "net/imap"

class ConnectableTest < ActiveSupport::TestCase
  test "mail_account includes connectable validations" do
    account = MailAccount.new(vessel: vessels(:one), name: "Test", short_code: "TE")
    assert_not account.valid?
    assert_includes account.errors[:imap_server], "can't be blank"
    assert_includes account.errors[:smtp_server], "can't be blank"
  end

  test "relay_account includes connectable validations" do
    account = RelayAccount.new(vessel: vessels(:one))
    assert_not account.valid?
    assert_includes account.errors[:imap_server], "can't be blank"
    assert_includes account.errors[:smtp_server], "can't be blank"
  end

  test "validates encryption mode inclusion" do
    account = mail_accounts(:gmail)
    account.imap_encryption = "bogus"
    assert_not account.valid?
    assert_includes account.errors[:imap_encryption], "is not included in the list"

    account.imap_encryption = "ssl"
    account.smtp_encryption = "bogus"
    assert_not account.valid?
    assert_includes account.errors[:smtp_encryption], "is not included in the list"
  end

  test "applies default ports from encryption mode" do
    account = MailAccount.new(
      vessel: vessels(:one), name: "Test", short_code: "TP",
      imap_server: "imap.test.com", imap_encryption: "ssl",
      smtp_server: "smtp.test.com", smtp_encryption: "starttls"
    )
    account.valid?
    assert_equal 993, account.imap_port
    assert_equal 587, account.smtp_port
  end

  test "applies default ports for starttls imap and ssl smtp" do
    account = MailAccount.new(
      vessel: vessels(:one), name: "Test", short_code: "TP",
      imap_server: "imap.test.com", imap_encryption: "starttls",
      smtp_server: "smtp.test.com", smtp_encryption: "ssl"
    )
    account.valid?
    assert_equal 143, account.imap_port
    assert_equal 465, account.smtp_port
  end

  test "does not override explicitly set ports" do
    account = MailAccount.new(
      vessel: vessels(:one), name: "Test", short_code: "TP",
      imap_server: "imap.test.com", imap_port: 2993, imap_encryption: "ssl",
      smtp_server: "smtp.test.com", smtp_port: 2587, smtp_encryption: "starttls"
    )
    account.valid?
    assert_equal 2993, account.imap_port
    assert_equal 2587, account.smtp_port
  end

  test "with_imap_connection yields connection and cleans up" do
    account = mail_accounts(:gmail)
    logged_out = false
    disconnected = false

    fake_imap = Object.new
    fake_imap.define_singleton_method(:login) { |_u, _p| true }
    fake_imap.define_singleton_method(:logout) { logged_out = true }
    fake_imap.define_singleton_method(:disconnect) { disconnected = true }

    original_new = Net::IMAP.method(:new)
    Net::IMAP.define_singleton_method(:new) do |_host, **_kwargs|
      fake_imap
    end

    yielded = nil
    account.with_imap_connection { |imap| yielded = imap }

    assert_equal fake_imap, yielded
    assert logged_out
    assert disconnected
  ensure
    Net::IMAP.define_singleton_method(:new, original_new)
  end

  test "with_imap_connection works for relay_account" do
    account = relay_accounts(:one)

    fake_imap = Object.new
    fake_imap.define_singleton_method(:login) { |_u, _p| true }
    fake_imap.define_singleton_method(:logout) { true }
    fake_imap.define_singleton_method(:disconnect) { true }

    original_new = Net::IMAP.method(:new)
    Net::IMAP.define_singleton_method(:new) do |_host, **_kwargs|
      fake_imap
    end

    yielded = nil
    account.with_imap_connection { |imap| yielded = imap }

    assert_equal fake_imap, yielded
  ensure
    Net::IMAP.define_singleton_method(:new, original_new)
  end

  test "with_imap_connection calls starttls when encryption is starttls" do
    account = mail_accounts(:gmail)
    account.imap_encryption = "starttls"
    starttls_called = false

    fake_imap = Object.new
    fake_imap.define_singleton_method(:login) { |_u, _p| true }
    fake_imap.define_singleton_method(:starttls) { starttls_called = true }
    fake_imap.define_singleton_method(:logout) { true }
    fake_imap.define_singleton_method(:disconnect) { true }

    original_new = Net::IMAP.method(:new)
    Net::IMAP.define_singleton_method(:new) do |_host, **_kwargs|
      fake_imap
    end

    account.with_imap_connection { |_imap| }
    assert starttls_called
  ensure
    Net::IMAP.define_singleton_method(:new, original_new)
  end
end
