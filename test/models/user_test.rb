require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "normalizes the email by stripping whitespace and downcasing" do
    user = User.create!(email: "  New.Person@Example.COM ", password: "password123")

    assert_equal "new.person@example.com", user.email
  end

  test "requires an email that looks like an address" do
    user = User.new(email: "not-an-email", password: "password123")

    assert_not user.valid?
    assert_includes user.errors[:email], "is invalid"
  end

  test "rejects a duplicate email regardless of case" do
    user = User.new(email: "ONE@example.com", password: "password123")

    assert_not user.valid?
    assert_includes user.errors[:email], "has already been taken"
  end

  test "requires a password of at least six characters" do
    user = User.new(email: "new@example.com", password: "short")

    assert_not user.valid?
    assert_includes user.errors[:password], "is too short (minimum is 6 characters)"
  end

  test "stays valid on update without touching the password" do
    user = users(:one)

    assert user.update(email: "renamed@example.com")
  end

  test "authenticate_by matches the fixture password" do
    assert_equal users(:one), User.authenticate_by(email: "one@example.com", password: "password123")
    assert_nil User.authenticate_by(email: "one@example.com", password: "wrong")
  end

  test "destroying a user removes its sessions" do
    user = User.create!(email: "temporary@example.com", password: "password123")
    user.sessions.create!

    assert_difference("Session.count", -1) { user.destroy! }
  end
end
