# An address derived from a wallet's extended public key. Branch 0 receives,
# branch 1 is change. Cached so each refresh resumes the gap-limit scan.
class Blockchain::Address < ApplicationRecord
  RECEIVE = 0
  CHANGE = 1

  belongs_to :connection

  validates :address, presence: true, uniqueness: { scope: :connection_id }
  validates :branch, inclusion: { in: [ RECEIVE, CHANGE ] }
  validates :index, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
