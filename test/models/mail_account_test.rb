require "test_helper"
require "net/imap"

class MailAccountTest < ActiveSupport::TestCase
  test "Net::IMAP parser tolerates COPYUID with uidvalidity=0 (Mailo bug)" do
    parser = Net::IMAP::ResponseParser.new
    response = parser.parse("A001 OK [COPYUID 0 18:21 27:30] copy completed\r\n")

    assert_equal "OK", response.name
    code = response.data.code
    assert_equal "COPYUID", code.name
    assert_nil code.data, "COPYUID with uidvalidity=0 should be swallowed to nil rather than crashing"
  end

  test "Net::IMAP parser tolerates APPENDUID with uidvalidity=0" do
    parser = Net::IMAP::ResponseParser.new
    response = parser.parse("A001 OK [APPENDUID 0 5] append completed\r\n")

    code = response.data.code
    assert_equal "APPENDUID", code.name
    assert_nil code.data
  end

  test "Net::IMAP parser still returns valid COPYUID data when uidvalidity is non-zero" do
    parser = Net::IMAP::ResponseParser.new
    response = parser.parse("A001 OK [COPYUID 42 18:21 27:30] copy completed\r\n")

    code = response.data.code
    assert_equal "COPYUID", code.name
    assert_equal 42, code.data.uidvalidity
  end

  test "copy_delete_expunge completes when uid_copy returns malformed COPYUID (server bug)" do
    account = mail_accounts(:gmail)
    uid_copy_called = false
    uid_store_deleted_called = false
    uid_expunge_called = false
    capabilities = [ "IMAP4rev1", "UIDPLUS" ]

    fake_imap = build_fake_imap
    fake_imap.define_singleton_method(:capability) { capabilities }
    fake_imap.define_singleton_method(:select) { |_folder| true }
    fake_imap.define_singleton_method(:uid_store) do |_uids, mode, flags|
      uid_store_deleted_called = true if mode == "+FLAGS" && flags.include?(:Deleted)
    end
    fake_imap.define_singleton_method(:uid_copy) do |_uids, _folder|
      uid_copy_called = true
      Net::IMAP::TaggedResponse.new(
        "A001", "OK",
        Net::IMAP::ResponseText.new(
          Net::IMAP::ResponseCode.new("COPYUID", nil),
          "copy completed"
        ),
        "A001 OK [COPYUID 0 1 2] copy completed\r\n"
      )
    end
    fake_imap.define_singleton_method(:uid_expunge) { |_uids| uid_expunge_called = true }
    fake_imap.define_singleton_method(:create) do |_name|
      raise Net::IMAP::NoResponseError.new(
        Net::IMAP::TaggedResponse.new("A001", "NO", Net::IMAP::ResponseText.new(nil, "exists"), "A001 NO exists\r\n")
      )
    end

    with_fake_imap(fake_imap) do
      account.mark_as_processed([ 1 ])
    end

    assert uid_copy_called
    assert uid_store_deleted_called, "Must continue to mark +Deleted even when COPYUID parse is suppressed"
    assert uid_expunge_called, "Must continue to expunge even when COPYUID parse is suppressed"
  end

  private
    def build_fake_imap
      fake = Object.new
      fake.define_singleton_method(:login) { |_u, _p| true }
      fake.define_singleton_method(:authenticate) { |_mech, _u, _p| true }
      fake.define_singleton_method(:logout) { true }
      fake.define_singleton_method(:disconnect) { true }
      fake
    end

    def with_fake_imap(fake_imap)
      original_new = Net::IMAP.method(:new)
      Net::IMAP.define_singleton_method(:new) { |_host, **_kwargs| fake_imap }
      yield
    ensure
      Net::IMAP.define_singleton_method(:new, original_new)
    end
end
