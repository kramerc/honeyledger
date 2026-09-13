# A WebAuthn credential registered by a user. `external_id` is the credential
# id the authenticator reports on every assertion, and `sign_count` is the
# authenticator's counter, checked on login to catch cloned credentials.
class Passkey < ApplicationRecord
  belongs_to :user

  validates :external_id, presence: true, uniqueness: true
  validates :public_key, presence: true
  validates :nickname, presence: true, length: { maximum: 64 }

  scope :by_recency, -> { order(created_at: :desc, id: :desc) }
end
