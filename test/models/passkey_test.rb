require "test_helper"

class PasskeyTest < ActiveSupport::TestCase
  test "requires an external id, a public key, and a nickname" do
    passkey = users(:one).passkeys.new

    assert_not passkey.valid?
    assert_includes passkey.errors[:external_id], "can't be blank"
    assert_includes passkey.errors[:public_key], "can't be blank"
    assert_includes passkey.errors[:nickname], "can't be blank"
  end

  test "rejects a credential id that is already registered" do
    passkey = users(:two).passkeys.new(external_id: passkeys(:laptop).external_id, public_key: "key", nickname: "Copy")

    assert_not passkey.valid?
    assert_includes passkey.errors[:external_id], "has already been taken"
  end

  test "limits the nickname length" do
    passkey = users(:one).passkeys.new(external_id: "fresh", public_key: "key", nickname: "x" * 65)

    assert_not passkey.valid?
    assert_includes passkey.errors[:nickname], "is too long (maximum is 64 characters)"
  end

  test "by_recency lists the newest first" do
    older = users(:one).passkeys.create!(external_id: "older", public_key: "key", nickname: "Older", created_at: 2.days.ago)
    newer = users(:one).passkeys.create!(external_id: "newer", public_key: "key", nickname: "Newer", created_at: 1.day.ago)

    assert_equal [ newer, older, passkeys(:laptop) ].sort_by { |passkey| -passkey.created_at.to_i }, users(:one).passkeys.by_recency.to_a
  end

  test "is removed with its user" do
    user = User.create!(email: "temporary@example.com", password: "password123")
    user.passkeys.create!(external_id: "temporary", public_key: "key", nickname: "Temporary")

    assert_difference("Passkey.count", -1) { user.destroy! }
  end
end
