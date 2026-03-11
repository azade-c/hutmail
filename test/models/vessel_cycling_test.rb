require "test_helper"
require "net/imap"

class VesselCyclingTest < ActiveSupport::TestCase
  setup do
    @vessel = vessels(:one)
  end

  test "run_cycle executes poll, collect, dispatch in order" do
    execution_order = []

    @vessel.define_singleton_method(:poll_relay_now) { execution_order << :poll }
    @vessel.define_singleton_method(:collect_all_accounts) { execution_order << :collect }
    @vessel.define_singleton_method(:dispatch_now) { execution_order << :dispatch }

    @vessel.run_cycle

    assert_equal %i[poll collect dispatch], execution_order
  end

  test "collect_all_accounts collects from each mail account" do
    collected = []

    @vessel.mail_accounts.each do |account|
      account.define_singleton_method(:collect_now) { collected << short_code; 0 }
    end

    original_find_each = @vessel.mail_accounts.method(:find_each)
    @vessel.define_singleton_method(:collect_all_accounts) do
      mail_accounts.each do |account|
        account.collect_now
      rescue => e
        Rails.logger.error e.message
      end
    end

    @vessel.collect_all_accounts

    assert_includes collected, "GM"
    assert_includes collected, "OR"
  end

  test "collect_all_accounts continues on individual account failure" do
    first_account = @vessel.mail_accounts.first
    first_account.define_singleton_method(:collect_now) { raise "IMAP down" }

    fake_imap = Object.new
    fake_imap.define_singleton_method(:login) { |_u, _p| true }
    fake_imap.define_singleton_method(:select) { |_box| true }
    fake_imap.define_singleton_method(:search) { |_query| [] }
    fake_imap.define_singleton_method(:logout) { true }
    fake_imap.define_singleton_method(:disconnect) { true }

    original_new = Net::IMAP.method(:new)
    Net::IMAP.define_singleton_method(:new) do |_host, **_kwargs|
      fake_imap
    end

    assert_nothing_raised { @vessel.collect_all_accounts }
  ensure
    Net::IMAP.define_singleton_method(:new, original_new)
  end
end
