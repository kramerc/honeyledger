class Lunchflow::Connection < ApplicationRecord
  belongs_to :user
  has_many :accounts, dependent: :destroy
  has_many :transactions, through: :accounts

  validates :user_id, uniqueness: true
  validates :api_key, presence: true

  def client
    LunchflowClient.new(api_key: api_key)
  end

  def refresh
    Lunchflow::RefreshJob.perform_later(self.id)
  end
end
