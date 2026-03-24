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

  test "validates imap_auth_method inclusion" do
    account = mail_accounts(:gmail)
    account.imap_auth_method = "bogus"
    assert_not account.valid?
    assert_includes account.errors[:imap_auth_method], "is not included in the list"
  end

  test "imap_auth_method allows nil" do
    account = mail_accounts(:gmail)
    account.imap_auth_method = nil
    account.valid?
    assert_empty account.errors[:imap_auth_method]
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

    fake_imap = build_fake_imap
    fake_imap.define_singleton_method(:logout) { logged_out = true }
    fake_imap.define_singleton_method(:disconnect) { disconnected = true }

    with_fake_imap(fake_imap) do
      yielded = nil
      account.with_imap_connection { |imap| yielded = imap }

      assert_equal fake_imap, yielded
      assert logged_out
      assert disconnected
    end
  end

  test "with_imap_connection works for relay_account" do
    account = relay_accounts(:one)

    fake_imap = build_fake_imap

    with_fake_imap(fake_imap) do
      yielded = nil
      account.with_imap_connection { |imap| yielded = imap }
      assert_equal fake_imap, yielded
    end
  end

  test "with_imap_connection calls starttls when encryption is starttls" do
    account = mail_accounts(:gmail)
    account.imap_encryption = "starttls"
    starttls_called = false

    fake_imap = build_fake_imap
    fake_imap.define_singleton_method(:starttls) { starttls_called = true }

    with_fake_imap(fake_imap) do
      account.with_imap_connection { |_imap| }
      assert starttls_called
    end
  end

  test "auth LOGIN direct when imap_auth_method is login" do
    account = mail_accounts(:gmail)
    account.imap_auth_method = "login"
    login_called = false
    authenticate_called = false

    fake_imap = build_fake_imap
    fake_imap.define_singleton_method(:login) { |_u, _p| login_called = true }
    fake_imap.define_singleton_method(:authenticate) { |*_args| authenticate_called = true }

    with_fake_imap(fake_imap) do
      account.with_imap_connection { |_imap| }
    end

    assert login_called
    assert_not authenticate_called
  end

  test "auth PLAIN when imap_auth_method is plain" do
    account = mail_accounts(:gmail)
    account.imap_auth_method = "plain"
    login_called = false
    authenticate_called = false
    auth_mechanism = nil

    fake_imap = build_fake_imap
    fake_imap.define_singleton_method(:login) { |_u, _p| login_called = true }
    fake_imap.define_singleton_method(:authenticate) { |mech, _u, _p| authenticate_called = true; auth_mechanism = mech }

    with_fake_imap(fake_imap) do
      account.with_imap_connection { |_imap| }
    end

    assert_not login_called
    assert authenticate_called
    assert_equal "PLAIN", auth_mechanism
  end

  test "cascade: LOGIN succeeds, memorizes login" do
    account = mail_accounts(:gmail)
    account.imap_auth_method = nil
    login_called = false

    fake_imap = build_fake_imap
    fake_imap.define_singleton_method(:login) { |_u, _p| login_called = true }

    with_fake_imap(fake_imap) do
      account.with_imap_connection { |_imap| }
    end

    assert login_called
    account.reload
    assert_equal "login", account.imap_auth_method
  end

  test "cascade: LOGIN fails, fallback PLAIN, memorizes plain" do
    account = mail_accounts(:gmail)
    account.imap_auth_method = nil
    authenticate_called = false

    fake_imap = build_fake_imap
    fake_imap.define_singleton_method(:login) { |_u, _p| raise Net::IMAP::NoResponseError.new(Net::IMAP::TaggedResponse.new("A001", "NO", Net::IMAP::ResponseText.new(nil, "auth failed"), "A001 NO auth failed\r\n")) }
    fake_imap.define_singleton_method(:authenticate) { |_mech, _u, _p| authenticate_called = true }

    with_fake_imap(fake_imap) do
      account.with_imap_connection { |_imap| }
    end

    assert authenticate_called
    account.reload
    assert_equal "plain", account.imap_auth_method
  end

  test "reset imap_auth_method when IMAP config changes" do
    account = mail_accounts(:gmail)
    account.update_column(:imap_auth_method, "login")
    assert_equal "login", account.imap_auth_method

    account.update!(imap_server: "new.imap.host")
    assert_nil account.imap_auth_method
  end

  test "reset imap_auth_method when IMAP username changes" do
    account = mail_accounts(:gmail)
    account.update_column(:imap_auth_method, "login")
    assert_equal "login", account.imap_auth_method

    account.update!(imap_username: "newuser@example.com")
    assert_nil account.imap_auth_method
  end

  test "reset imap_auth_method when IMAP password changes" do
    account = mail_accounts(:gmail)
    account.update_column(:imap_auth_method, "plain")
    assert_equal "plain", account.imap_auth_method

    account.update!(imap_password: "newpassword123")
    assert_nil account.imap_auth_method
  end

  test "memorized auth fails, skips failed method, memorizes new method" do
    account = mail_accounts(:gmail)
    account.update_column(:imap_auth_method, "login")
    authenticate_called = false

    no_response = Net::IMAP::NoResponseError.new(
      Net::IMAP::TaggedResponse.new("A001", "NO", Net::IMAP::ResponseText.new(nil, "login disabled"), "A001 NO login disabled\r\n")
    )

    login_attempts = 0
    fake_imap = build_fake_imap
    fake_imap.define_singleton_method(:login) { |_u, _p| login_attempts += 1; raise no_response }
    fake_imap.define_singleton_method(:authenticate) { |_mech, _u, _p| authenticate_called = true }

    with_fake_imap(fake_imap) do
      account.with_imap_connection { |_imap| }
    end

    assert authenticate_called
    assert_equal 1, login_attempts
    account.reload
    assert_equal "plain", account.imap_auth_method
  end

  test "memorized auth reconnection uses memorized method directly" do
    account = mail_accounts(:gmail)
    account.update_column(:imap_auth_method, "plain")
    login_called = false
    authenticate_called = false

    fake_imap = build_fake_imap
    fake_imap.define_singleton_method(:login) { |_u, _p| login_called = true }
    fake_imap.define_singleton_method(:authenticate) { |_mech, _u, _p| authenticate_called = true }

    with_fake_imap(fake_imap) do
      account.with_imap_connection { |_imap| }
    end

    assert_not login_called
    assert authenticate_called
  end

  test "cascade raises when both LOGIN and PLAIN fail" do
    account = mail_accounts(:gmail)
    account.imap_auth_method = nil

    no_response = Net::IMAP::NoResponseError.new(
      Net::IMAP::TaggedResponse.new("A001", "NO", Net::IMAP::ResponseText.new(nil, "auth failed"), "A001 NO auth failed\r\n")
    )

    fake_imap = build_fake_imap
    fake_imap.define_singleton_method(:login) { |_u, _p| raise no_response }
    fake_imap.define_singleton_method(:authenticate) { |*_args| raise no_response }

    with_fake_imap(fake_imap) do
      assert_raises(Net::IMAP::NoResponseError) do
        account.with_imap_connection { |_imap| }
      end
    end

    account.reload
    assert_nil account.imap_auth_method
  end

  test "MOVE falls back to copy_delete_expunge when uid_move fails despite MOVE capability" do
    account = mail_accounts(:gmail)
    account.update_column(:imap_move_strategy, "move")
    copy_called = false
    expunge_called = false

    no_response = Net::IMAP::NoResponseError.new(
      Net::IMAP::TaggedResponse.new("A001", "NO", Net::IMAP::ResponseText.new(nil, "move failed"), "A001 NO move failed\r\n")
    )

    fake_imap = build_fake_imap
    fake_imap.define_singleton_method(:capability) { [ "IMAP4rev1", "MOVE", "UIDPLUS" ] }
    fake_imap.define_singleton_method(:select) { |_folder| true }
    fake_imap.define_singleton_method(:uid_store) { |*_args| true }
    fake_imap.define_singleton_method(:uid_move) { |_uids, _folder| raise no_response }
    fake_imap.define_singleton_method(:uid_copy) { |_uids, _folder| copy_called = true }
    fake_imap.define_singleton_method(:uid_expunge) { |_uids| expunge_called = true }
    fake_imap.define_singleton_method(:create) { |_name| raise Net::IMAP::NoResponseError.new(Net::IMAP::TaggedResponse.new("A001", "NO", Net::IMAP::ResponseText.new(nil, "exists"), "A001 NO exists\r\n")) }

    with_fake_imap(fake_imap) do
      account.mark_as_processed([ 1 ])
    end

    assert copy_called
    assert expunge_called
    account.reload
    assert_equal "copy_delete_expunge", account.imap_move_strategy
  end

  test "MOVE via capability check when MOVE capability present" do
    account = mail_accounts(:gmail)
    uid_move_called = false
    capabilities = [ "IMAP4rev1", "MOVE", "UIDPLUS" ]

    fake_imap = build_fake_imap
    fake_imap.define_singleton_method(:capability) { capabilities }
    fake_imap.define_singleton_method(:select) { |_folder| true }
    fake_imap.define_singleton_method(:uid_store) { |*_args| true }
    fake_imap.define_singleton_method(:uid_move) { |_uids, _folder| uid_move_called = true }
    fake_imap.define_singleton_method(:create) { |_name| raise Net::IMAP::NoResponseError.new(Net::IMAP::TaggedResponse.new("A001", "NO", Net::IMAP::ResponseText.new(nil, "exists"), "A001 NO exists\r\n")) }

    with_fake_imap(fake_imap) do
      account.mark_as_processed([ 1 ])
    end

    assert uid_move_called
  end

  test "MOVE falls back to copy_delete_expunge when MOVE capability absent" do
    account = mail_accounts(:gmail)
    uid_copy_called = false
    uid_store_calls = 0
    expunge_called = false
    capabilities = [ "IMAP4rev1", "UIDPLUS" ]

    fake_imap = build_fake_imap
    fake_imap.define_singleton_method(:capability) { capabilities }
    fake_imap.define_singleton_method(:select) { |_folder| true }
    fake_imap.define_singleton_method(:uid_store) { |*_args| uid_store_calls += 1 }
    fake_imap.define_singleton_method(:uid_copy) { |_uids, _folder| uid_copy_called = true }
    fake_imap.define_singleton_method(:uid_expunge) { |_uids| expunge_called = true }
    fake_imap.define_singleton_method(:create) { |_name| raise Net::IMAP::NoResponseError.new(Net::IMAP::TaggedResponse.new("A001", "NO", Net::IMAP::ResponseText.new(nil, "exists"), "A001 NO exists\r\n")) }

    with_fake_imap(fake_imap) do
      account.mark_as_processed([ 1 ])
    end

    assert uid_copy_called
    assert expunge_called
  end

  test "UID EXPUNGE used when UIDPLUS capability available" do
    account = mail_accounts(:gmail)
    uid_expunge_called = false
    expunge_called = false
    capabilities = [ "IMAP4rev1", "UIDPLUS" ]

    fake_imap = build_fake_imap
    fake_imap.define_singleton_method(:capability) { capabilities }
    fake_imap.define_singleton_method(:select) { |_folder| true }
    fake_imap.define_singleton_method(:uid_store) { |*_args| true }
    fake_imap.define_singleton_method(:uid_copy) { |_uids, _folder| true }
    fake_imap.define_singleton_method(:uid_expunge) { |_uids| uid_expunge_called = true }
    fake_imap.define_singleton_method(:expunge) { expunge_called = true }
    fake_imap.define_singleton_method(:create) { |_name| raise Net::IMAP::NoResponseError.new(Net::IMAP::TaggedResponse.new("A001", "NO", Net::IMAP::ResponseText.new(nil, "exists"), "A001 NO exists\r\n")) }

    with_fake_imap(fake_imap) do
      account.mark_as_processed([ 1 ])
    end

    assert uid_expunge_called
    assert_not expunge_called
  end

  test "global EXPUNGE used when UIDPLUS capability not available" do
    account = mail_accounts(:gmail)
    uid_expunge_called = false
    expunge_called = false
    capabilities = [ "IMAP4rev1" ]

    fake_imap = build_fake_imap
    fake_imap.define_singleton_method(:capability) { capabilities }
    fake_imap.define_singleton_method(:select) { |_folder| true }
    fake_imap.define_singleton_method(:uid_store) { |*_args| true }
    fake_imap.define_singleton_method(:uid_copy) { |_uids, _folder| true }
    fake_imap.define_singleton_method(:uid_expunge) { |_uids| uid_expunge_called = true }
    fake_imap.define_singleton_method(:expunge) { expunge_called = true }
    fake_imap.define_singleton_method(:create) { |_name| raise Net::IMAP::NoResponseError.new(Net::IMAP::TaggedResponse.new("A001", "NO", Net::IMAP::ResponseText.new(nil, "exists"), "A001 NO exists\r\n")) }

    with_fake_imap(fake_imap) do
      account.mark_as_processed([ 1 ])
    end

    assert_not uid_expunge_called
    assert expunge_called
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
