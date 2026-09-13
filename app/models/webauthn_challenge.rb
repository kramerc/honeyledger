# A one-use WebAuthn challenge, kept server-side so that consuming it is
# atomic: the cookie session cannot do that, because two overlapping requests
# carrying the same cookie would each see the challenge still present.
#
# Registration challenges remember the user they were issued to, so a
# ceremony started under one account cannot complete under another.
class WebauthnChallenge < ApplicationRecord
  TTL = 5.minutes
  PURPOSES = %w[ registration authentication ].freeze

  belongs_to :user, optional: true

  validates :purpose, inclusion: { in: PURPOSES }
  validates :challenge, presence: true

  scope :expired, -> { where(expires_at: ..Time.current) }

  def self.issue(purpose:, challenge:, user: nil)
    expired.delete_all
    create!(purpose: purpose, challenge: challenge, user: user, expires_at: TTL.from_now)
  end

  # Returns the challenge string only if this call is the one that deleted
  # the row, so concurrent requests cannot both succeed. Also refuses a row
  # issued for another purpose or another user, or one that has expired: the
  # expiry is part of the delete itself, so a request paused between the read
  # and the delete cannot consume a challenge that expired meanwhile.
  def self.consume(id, purpose:, user: nil)
    row = find_by(id: id, purpose: purpose, user_id: user&.id)
    return nil if row.nil?

    row.challenge if where(id: row.id, expires_at: Time.current..).delete_all == 1
  end
end
