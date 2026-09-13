require "test_helper"

class WebauthnChallengeTest < ActiveSupport::TestCase
  test "issue stores the challenge with an expiry and purges expired rows" do
    stale = WebauthnChallenge.create!(purpose: "authentication", challenge: "stale", expires_at: 1.minute.ago)

    issued = WebauthnChallenge.issue(purpose: "registration", challenge: "fresh", user: users(:one))

    assert_equal users(:one), issued.user
    assert_in_delta WebauthnChallenge::TTL.from_now, issued.expires_at, 5.seconds
    assert_not WebauthnChallenge.exists?(stale.id)
  end

  test "consume returns the challenge once and then never again" do
    issued = WebauthnChallenge.issue(purpose: "authentication", challenge: "once")

    assert_equal "once", WebauthnChallenge.consume(issued.id, purpose: "authentication")
    assert_nil WebauthnChallenge.consume(issued.id, purpose: "authentication")
    assert_not WebauthnChallenge.exists?(issued.id)
  end

  test "consume refuses a challenge issued for another purpose" do
    issued = WebauthnChallenge.issue(purpose: "registration", challenge: "reg", user: users(:one))

    assert_nil WebauthnChallenge.consume(issued.id, purpose: "authentication")
    assert WebauthnChallenge.exists?(issued.id)
  end

  test "consume refuses a registration challenge issued to another user" do
    issued = WebauthnChallenge.issue(purpose: "registration", challenge: "reg", user: users(:one))

    assert_nil WebauthnChallenge.consume(issued.id, purpose: "registration", user: users(:two))
    assert_nil WebauthnChallenge.consume(issued.id, purpose: "registration")
    assert_equal "reg", WebauthnChallenge.consume(issued.id, purpose: "registration", user: users(:one))
  end

  test "consume refuses an expired challenge and leaves it for the next purge" do
    issued = WebauthnChallenge.issue(purpose: "authentication", challenge: "old")
    issued.update!(expires_at: 1.second.ago)

    assert_nil WebauthnChallenge.consume(issued.id, purpose: "authentication")
    assert WebauthnChallenge.exists?(issued.id)
  end

  test "consume refuses a challenge that expires between the read and the delete" do
    issued = WebauthnChallenge.issue(purpose: "authentication", challenge: "racing")
    # Hand back a row that still looks valid in memory while the database row
    # expires underneath it, as a request paused past the deadline would see.
    stale_read = ->(**) {
      WebauthnChallenge.where(id: issued.id).update_all(expires_at: 1.second.ago)
      issued
    }

    WebauthnChallenge.stub(:find_by, stale_read) do
      assert_nil WebauthnChallenge.consume(issued.id, purpose: "authentication")
    end
    assert WebauthnChallenge.exists?(issued.id)
  end

  test "consume tolerates a missing id" do
    assert_nil WebauthnChallenge.consume(nil, purpose: "authentication")
  end

  test "requires a known purpose and a challenge" do
    challenge = WebauthnChallenge.new(purpose: "other", challenge: "", expires_at: 1.minute.from_now)

    assert_not challenge.valid?
    assert_includes challenge.errors[:purpose], "is not included in the list"
    assert_includes challenge.errors[:challenge], "can't be blank"
  end
end
