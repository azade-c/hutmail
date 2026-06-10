require "test_helper"

class Vessels::BundlesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @vessel = vessels(:one)
    sign_in_as @user
  end

  test "index lists bundles and offers a manual dispatch button" do
    get vessel_bundles_path(@vessel)

    assert_response :success
    assert_select "form[action=?]", vessel_dispatch_path(@vessel) do
      assert_select "button:not([disabled])", text: "Envoyer maintenant"
    end
  end

  test "index greys the dispatch button when no messages are bundleable" do
    MessageDigest.where(
      mail_account_id: @vessel.mail_accounts.select(:id)
    ).update_all(status: MessageDigest.statuses.fetch("bundled"))

    get vessel_bundles_path(@vessel)

    assert_response :success
    assert_select "form[action=?]", vessel_dispatch_path(@vessel) do
      assert_select "button[disabled]", text: "Envoyer maintenant"
    end
  end

  test "index rejects access from unrelated user" do
    sign_in_as users(:no_vessel)
    get vessel_bundles_path(@vessel)
    assert_redirected_to vessels_path
  end

  private
    def sign_in_as(user)
      post session_path, params: { email_address: user.email_address, password: "password" }
    end
end
