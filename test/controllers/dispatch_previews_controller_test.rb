require "test_helper"

class DispatchPreviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @vessel = vessels(:one)
    sign_in_as @user
  end

  test "show renders preview with messages ready for bundling" do
    get vessel_dispatch_preview_path(@vessel)

    assert_response :success
    assert_select "turbo-frame#dispatch-preview"
    assert_select ".btn__group"
    assert_select "form[action='#{vessel_dispatch_preview_path(@vessel)}'][data-turbo-frame='dispatch-preview']"
    assert_select "form[action='#{vessel_dispatch_path(@vessel)}'][data-turbo-frame='_top']"
    assert_select ".bundle-preview"
  end

  test "show renders empty state without messages ready for bundling" do
    MessageDigest.where(
      mail_account_id: @vessel.mail_accounts.select(:id)
    ).update_all(status: MessageDigest.statuses.fetch("bundled"))

    get vessel_dispatch_preview_path(@vessel)

    assert_response :success
    assert_select ".empty-state"
  end

  test "show does not create any bundle record" do
    assert_no_difference "Bundle.count" do
      get vessel_dispatch_preview_path(@vessel)
    end
  end

  test "show rejects access to unrelated vessel" do
    sign_in_as users(:no_vessel)
    get vessel_dispatch_preview_path(@vessel)
    assert_redirected_to vessels_path
  end

  private
    def sign_in_as(user)
      post session_path, params: { email_address: user.email_address, password: "password" }
    end
end
