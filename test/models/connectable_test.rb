require "test_helper"
require "net/imap"

class ConnectableTest < ActiveSupport::TestCase
  test "mail_account includes connectable validations" do
    account = MailAccount.new(vessel: vessels(:one), name: "Test", short_code: "TE")
    assert_not account.valid?
    assert_includes account.errors[:imap_server], "can't be blank"
    assert_includes account.errors[:imap_port], "can't be blank"
    assert_includes account.errors[:smtp_server], "can't be blank"
    assert_includes account.errors[:smtp_port], "can't be blank"
  end

  test "relay_account includes connectable validations" do
    account = RelayAccount.new(vessel: vessels(:one))
    assert_not account.valid?
    assert_includes account.errors[:imap_server], "can't be blank"
    assert_includes account.errors[:smtp_server], "can't be blank"
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
end
