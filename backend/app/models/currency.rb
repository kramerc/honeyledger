class Currency < ApplicationRecord
  has_many :accounts, dependent: :restrict_with_error
  has_many :transactions, dependent: :restrict_with_error
  has_many :fx_transactions, class_name: "Transaction", dependent: :restrict_with_error

  enum :kind, { fiat: 0, crypto: 1 }, default: :fiat

  validates :code, presence: true, uniqueness: true, length: { maximum: 10 }
  validates :name, :symbol, :decimal_places, presence: true
  validates :decimal_places, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 18 }

  scope :active, -> { where(active: true) }
  scope :fiat, -> { where(kind: :fiat) }
  scope :crypto, -> { where(kind: :crypto) }
end
