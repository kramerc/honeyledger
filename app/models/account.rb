class Account < ApplicationRecord
  belongs_to :user
  belongs_to :currency, optional: true

  # Transactions (source, destination, opening balance)
  before_destroy -> { opening_balance_transaction.destroy! }, if: -> { opening_balance_transaction.present? && empty? }
  has_many :src_transactions, class_name: "Transaction", foreign_key: "src_account_id", dependent: :restrict_with_error
  has_many :dest_transactions, class_name: "Transaction", foreign_key: "dest_account_id", dependent: :restrict_with_error
  before_validation :assign_opening_balance_transaction_attributes, if: -> { opening_balance_transaction.present? }
  validate :opening_balance_transaction_is_valid, if: -> { opening_balance_transaction.present? }
  after_save :save_or_destroy_opening_balance_transaction, if: -> { opening_balance_transaction.present? }

  has_one :simplefin_account, class_name: "Simplefin::Account", foreign_key: :ledger_account_id, dependent: :nullify

  enum :kind, %i[ asset liability equity expense revenue ]
  SOURCEABLE = %i[ asset liability equity revenue ].freeze
  DESTINABLE = %i[ asset liability equity expense ].freeze
  scope :sourceable, -> { where(kind: SOURCEABLE).real }
  scope :destinable, -> { where(kind: DESTINABLE).real }

  validates :currency, presence: true, unless: :virtual?
  validates :name, presence: true

  scope :real, -> { where(virtual: false) }
  scope :virtual, -> { where(virtual: true) }
  scope :linkable, -> { where(kind: %i[ asset liability ]) }
  scope :unlinked, -> { left_joins(:simplefin_account).where(simplefin_accounts: { id: nil }) }

  def self.opening_balance_for(user:, kind:)
    attributes = { user: user, kind: kind, name: "Opening Balance", virtual: true }
    Account.find_or_create_by!(attributes)
  rescue ActiveRecord::RecordNotUnique
    Account.find_by(attributes) || raise
  end

  def build_opening_balance_transaction(transaction_attributes = {})
    @opening_balance_transaction = Transaction.new({
      user: user,
      currency: currency,
      opening_balance: true,
      opening_balance_target_account: self
    }.merge(transaction_attributes))
  end

  def opening_balance_transaction
    @opening_balance_transaction ||= Transaction.where(src_account: self)
      .or(Transaction.where(dest_account: self))
      .opening_balances
      .first
  end

  def opening_balance_transaction=(transaction)
    @opening_balance_transaction = transaction
  end

  def opening_balance_transaction_attributes=(transaction_attributes)
    transaction = opening_balance_transaction || build_opening_balance_transaction
    transaction.assign_attributes(transaction_attributes)
    @opening_balance_transaction = transaction
  end

  def empty?
    count = Transaction.where(src_account: self).or(Transaction.where(dest_account: self)).count
    count -= 1 if opening_balance_transaction.present?
    count.zero?
  end

  def real?
    !virtual?
  end

  # Check if a user has access to this account
  # Currently checks ownership, but can be extended for sharing
  def accessible_by?(user)
    user_id == user.id
  end

  private

    def assign_opening_balance_transaction_attributes
      opening_balance_transaction.user = user
      opening_balance_transaction.currency = currency
      opening_balance_transaction.opening_balance = true
      opening_balance_transaction.opening_balance_target_account = self
    end

    def opening_balance_transaction_is_valid
      unless opening_balance_transaction.valid?
        opening_balance_transaction.errors.each do |error|
          if %i[ amount amount_minor ].include?(error.attribute) && %i[ blank zero ].include?(error.type)
            # Skip these errors as the transaction will be destroyed instead
            next
          end

          errors.objects.append(ActiveModel::NestedError.new(opening_balance_transaction, error, attribute: :"opening_balance_transaction.#{error.attribute}"))
        end
      end
    end

    def save_or_destroy_opening_balance_transaction
      if opening_balance_transaction.amount_written? && opening_balance_transaction.amount.to_d.zero?
        opening_balance_transaction.destroy!
      elsif !opening_balance_transaction.amount_written? && opening_balance_transaction.amount_minor.to_i.zero?
        opening_balance_transaction.destroy!
      else
        opening_balance_transaction.save!
      end
    end
end
