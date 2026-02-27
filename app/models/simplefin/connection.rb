class Simplefin::Connection < ApplicationRecord
  belongs_to :user
  has_many :accounts, dependent: :destroy
  has_many :transactions, through: :accounts

  validates :user_id, uniqueness: true

  attr_accessor :setup_token, :demo

  DEMO_URL = "https://demo:demo@beta-bridge.simplefin.org/simplefin"

  def client
    SimplefinClient.new(url: self.url)
  end

  def claim!
    return claim_demo! if ActiveModel::Type::Boolean.new.cast(self.demo)

    raise "Setup token required to claim connection" if self.setup_token.blank?

    self.url = self.client.claim(self.setup_token)
    self.refreshed_at = nil
    self.save!

    self.refresh
  end

  def claim_demo!
    self.url = DEMO_URL
    self.refreshed_at = nil
    self.save!

    self.refresh
  end

  def refresh
    Simplefin::RefreshJob.perform_later(self.id)
  end
end
