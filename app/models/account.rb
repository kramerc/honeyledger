class Account < ApplicationRecord
  belongs_to :user
  belongs_to :currency

  has_many :src_transactions, class_name: "Transaction", foreign_key: "src_account_id", dependent: :restrict_with_error
  has_many :dest_transactions, class_name: "Transaction", foreign_key: "dest_account_id", dependent: :restrict_with_error
  has_one :opening_balance_transaction, -> { opening_balances }, class_name: "Transaction", foreign_key: "dest_account_id", dependent: :destroy
  accepts_nested_attributes_for :opening_balance_transaction

  has_one :simplefin_account, class_name: "Simplefin::Account", foreign_key: :ledger_account_id, dependent: :nullify

  enum :kind, { asset: 0, liability: 1, equity: 2, expense: 3, revenue: 4 }
  SOURCEABLE = [ :asset, :liability, :equity, :revenue ].freeze
  DESTINABLE = [ :asset, :liability, :equity, :expense ].freeze

  validates :name, presence: true

  scope :assets, -> { where(kind: :asset) }
  scope :liabilities, -> { where(kind: :liability) }
  scope :equities, -> { where(kind: :equity) }
  scope :expenses, -> { where(kind: :expense) }
  scope :revenues, -> { where(kind: :revenue) }

  scope :sourceable, -> { where(kind: SOURCEABLE) }
  scope :destinable, -> { where(kind: DESTINABLE) }

  scope :linkable, -> { where(kind: [ :asset, :liability ]) }
  scope :unlinked, -> { left_joins(:simplefin_account).where(simplefin_accounts: { id: nil }) }

  # Check if a user has access to this account
  # Currently checks ownership, but can be extended for sharing
  def accessible_by?(user)
    user_id == user.id
  end
end
