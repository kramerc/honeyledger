class Transaction < ApplicationRecord
  include Minorable
  unminorable :amount_minor, with: :currency
  unminorable :fx_amount_minor, with: :fx_currency

  belongs_to :user
  belongs_to :sourceable, polymorphic: true, optional: true

  belongs_to :category, optional: true

  belongs_to :src_account, optional: true, class_name: "Account"
  belongs_to :dest_account, optional: true, class_name: "Account"
  validates_presence_of :src_account, :dest_account, message: :required

  belongs_to :currency
  belongs_to :fx_currency, class_name: "Currency", optional: true

  belongs_to :parent_transaction, class_name: "Transaction", optional: true
  has_many :child_transactions, class_name: "Transaction", foreign_key: "parent_transaction_id", dependent: :destroy

  before_validation :assign_currency_from_dest_account, unless: :opening_balance?
  before_validation :assign_cleared_at_from_cleared, unless: :opening_balance?

  after_create :mark_parent_as_split, if: :parent_transaction_id?
  after_destroy :unmark_parent_if_last_child, if: :parent_transaction_id?
  after_save :transfer_account_balances
  after_destroy :reverse_account_balances

  scope :opening_balances, -> { where(opening_balance: true) }

  validates :amount_minor, numericality: { allow_blank: true, unless: :amount_written? } # Blank is translated to 0
  validates :transacted_at, presence: true

  validate :src_account_accessible_to_user
  validate :dest_account_accessible_to_user

  validate :accounts_cannot_be_same, unless: -> { src_account_id.nil? || dest_account_id.nil? }
  validate :not_expense_to_revenue, if: -> { src_account&.expense? && dest_account&.revenue? }
  validate :not_revenue_to_expense, if: -> { src_account&.revenue? && dest_account&.expense? }

  def cleared
    return @cleared if defined?(@cleared)
    cleared_at.present?
  end

  def cleared=(value)
    @cleared = ActiveModel::Type::Boolean.new.cast(value)
  end

  def has_fx?
    fx_amount_minor.present? && fx_currency.present?
  end

  # Returns the real (non-virtual) account taking part in this opening balance transaction —
  # the one that required the opening balance to be set.
  def opening_balance_target_account
    return nil unless opening_balance?
    [ src_account, dest_account ].find { |a| a&.real? }
  end

  private

    def assign_currency_from_dest_account
      self.currency = dest_account.currency if dest_account.present? && !dest_account.virtual?
    end

    def assign_cleared_at_from_cleared
      return unless defined?(@cleared)

      if @cleared
        self.cleared_at ||= Time.current
      else
        self.cleared_at = nil
      end
    end

    def mark_parent_as_split
      parent_transaction.update(split: true)
    end

    def unmark_parent_if_last_child
      parent_transaction.update(split: false) if parent_transaction.child_transactions.empty?
    end

    def transfer_account_balances
      return unless saved_change_to_amount_minor? || saved_change_to_fx_amount_minor? ||
                    saved_change_to_src_account_id? || saved_change_to_dest_account_id?

      previous_amount_minor = amount_minor_before_last_save || 0
      previous_fx_amount_minor = fx_amount_minor_before_last_save
      # For the src side, use the FX amount if the previous posting had one
      previous_src_amount_minor = previous_fx_amount_minor.nil? ? previous_amount_minor : previous_fx_amount_minor
      previous_src_id = src_account_id_before_last_save
      previous_dest_id = dest_account_id_before_last_save

      # For the src side, use fx_amount_minor when present (src account holds a different currency)
      src_amount_minor = fx_amount_minor.nil? ? amount_minor : fx_amount_minor

      Account.transaction do
        # Reverse the old posting (only when accounts existed before this save)
        if previous_src_id.present? && previous_dest_id.present?
          previous_src = Account.find_by(id: previous_src_id)
          previous_dest = Account.find_by(id: previous_dest_id)
          Account.update_counters(previous_src.id, balance_minor: previous_src_amount_minor) if previous_src&.real?
          Account.update_counters(previous_dest.id, balance_minor: -previous_amount_minor) if previous_dest&.real?
        end

        # Apply the new posting
        if src_account_id.present? && dest_account_id.present?
          Account.update_counters(src_account_id, balance_minor: -src_amount_minor) if src_account&.real?
          Account.update_counters(dest_account_id, balance_minor: amount_minor) if dest_account&.real?
        end
      end
    end

    def reverse_account_balances
      # Use persisted (_was) values so reassigning associations in-memory before destroy! doesn't reverse the wrong accounts
      return if amount_minor_was.nil?

      persisted_src = Account.find_by(id: src_account_id_was)
      persisted_dest = Account.find_by(id: dest_account_id_was)

      # For the src side, reverse by the FX amount if the transaction had one
      src_amount_minor_was = fx_amount_minor_was.nil? ? amount_minor_was : fx_amount_minor_was

      Account.transaction do
        Account.update_counters(persisted_src.id, balance_minor: src_amount_minor_was) if persisted_src&.real?
        Account.update_counters(persisted_dest.id, balance_minor: -amount_minor_was) if persisted_dest&.real?
      end
    end

    def src_account_accessible_to_user
      return if src_account.blank? || user.blank?

      unless src_account.accessible_by?(user)
        errors.add(:src_account, "must be accessible to you")
      end
    end

    def dest_account_accessible_to_user
      return if dest_account.blank? || user.blank?

      unless dest_account.accessible_by?(user)
        errors.add(:dest_account, "must be accessible to you")
      end
    end

    def accounts_cannot_be_same
      if src_account_id == dest_account_id
        errors.add(:src_account, "cannot be the same as dest account")
      end
    end

    def not_revenue_to_expense
      if src_account.revenue? && dest_account.expense?
        errors.add(:src_account, "cannot be a revenue account to an expense dest account")
      end
    end

    def not_expense_to_revenue
      if src_account.expense? && dest_account.revenue?
        errors.add(:src_account, "cannot be an expense account to a revenue dest account")
      end
    end
end
