require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  test "GET new renders sign-up form" do
    get new_user_path
    assert_response :success
    assert_select "form"
  end

  test "POST create with valid params signs up and redirects to dashboard" do
    assert_difference "User.count", 1 do
      post user_path, params: { user: {
        email_address: "newbie@example.com",
        password: "secretpass1234"
      } }
    end

    assert_redirected_to dashboard_path
    assert cookies[:session_id].present?
  end

  test "POST create with missing password re-renders form" do
    assert_no_difference "User.count" do
      post user_path, params: { user: {
        email_address: "newbie@example.com",
        password: ""
      } }
    end

    assert_response :unprocessable_entity
  end

  test "POST create with duplicate email re-renders form" do
    User.create!(email_address: "taken@example.com", password: "secretpass1234")

    assert_no_difference "User.count" do
      post user_path, params: { user: {
        email_address: "taken@example.com",
        password: "secretpass1234"
      } }
    end

    assert_response :unprocessable_entity
  end

  test "POST create with short password re-renders form" do
    assert_no_difference "User.count" do
      post user_path, params: { user: {
        email_address: "newbie@example.com",
        password: "tooshort"
      } }
    end

    assert_response :unprocessable_entity
  end
end
