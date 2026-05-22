require "test_helper"

class Vessels::DispatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @vessel = vessels(:one)
    sign_in_as @user
  end

  test "create dispatches bundle and redirects to bundle page" do
    fake_bundle = Bundle.create!(
      vessel: @vessel,
      status: "sent",
      sent_at: Time.current,
      messages_count: 1,
      total_stripped_size: 100
    )

    original_collect = Vessel.instance_method(:collect_all_accounts)
    original_dispatch = Vessel.instance_method(:dispatch_now)
    Vessel.define_method(:collect_all_accounts) { 1 }
    Vessel.define_method(:dispatch_now) { fake_bundle }

    post vessel_dispatch_path(@vessel)

    assert_redirected_to bundle_path(fake_bundle)
    assert_match(/Dépêche envoyée/, flash[:notice])
  ensure
    Vessel.define_method(:collect_all_accounts, original_collect)
    Vessel.define_method(:dispatch_now, original_dispatch)
  end

  test "create completes successfully even when IMAP courtesy step fails (Mailo COPYUID bug)" do
    fake_bundle = Bundle.create!(
      vessel: @vessel,
      status: "sent",
      sent_at: Time.current,
      messages_count: 2,
      total_stripped_size: 500
    )

    original_collect = Vessel.instance_method(:collect_all_accounts)
    original_dispatch = Vessel.instance_method(:dispatch_now)

    Vessel.define_method(:collect_all_accounts) { 2 }
    Vessel.define_method(:dispatch_now) do
      Rails.logger.warn "Failed to process IMAP for MailAccount#1: nz-number must be non-zero unsigned 32-bit integer: 0"
      fake_bundle
    end

    post vessel_dispatch_path(@vessel)

    assert_redirected_to bundle_path(fake_bundle)
    assert_equal "sent", fake_bundle.reload.status
  ensure
    Vessel.define_method(:collect_all_accounts, original_collect)
    Vessel.define_method(:dispatch_now, original_dispatch)
  end

  test "create redirects with no-messages notice when nothing to dispatch" do
    original_collect = Vessel.instance_method(:collect_all_accounts)
    original_dispatch = Vessel.instance_method(:dispatch_now)
    Vessel.define_method(:collect_all_accounts) { 0 }
    Vessel.define_method(:dispatch_now) { nil }

    post vessel_dispatch_path(@vessel)

    assert_redirected_to vessel_path(@vessel)
    assert_equal "Aucun message à dépêcher", flash[:notice]
  ensure
    Vessel.define_method(:collect_all_accounts, original_collect)
    Vessel.define_method(:dispatch_now, original_dispatch)
  end

  test "create rejects access from unrelated user" do
    sign_in_as users(:no_vessel)
    post vessel_dispatch_path(@vessel)
    assert_redirected_to vessels_path
  end

  private
    def sign_in_as(user)
      post session_path, params: { email_address: user.email_address, password: "password" }
    end
end
