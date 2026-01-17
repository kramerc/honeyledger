class Account < ApplicationRecord
  belongs_to :user
  belongs_to :currency

  has_many :src_transactions, class_name: "Transaction", foreign_key: "src_account_id", dependent: :restrict_with_error
  has_many :dest_transactions, class_name: "Transaction", foreign_key: "dest_account_id", dependent: :restrict_with_error
  has_one :opening_balance_transaction, -> { opening_balances }, class_name: "Transaction", foreign_key: "dest_account_id", dependent: :destroy
  accepts_nested_attributes_for :opening_balance_transaction

  has_one :simplefin_account, dependent: :nullify

  enum :kind, { asset: 0, liability: 1, equity: 2, expense: 3, revenue: 4 }

  validates :name, presence: true

  scope :assets, -> { where(kind: :asset) }
  scope :liabilities, -> { where(kind: :liability) }
  scope :equities, -> { where(kind: :equity) }
  scope :expenses, -> { where(kind: :expense) }
  scope :revenues, -> { where(kind: :revenue) }

  scope :sourceable, -> { where(kind: [ :asset, :liability, :equity, :revenue ]) }
  scope :destinable, -> { where(kind: [ :asset, :liability, :equity, :expense ]) }
end
