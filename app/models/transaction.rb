class Transaction < ApplicationRecord
  include Minorable
  unminorable :amount_minor, with: :currency
  unminorable :fx_amount_minor, with: :fx_currency

  belongs_to :user
  belongs_to :sourceable, polymorphic: true, optional: true

  belongs_to :category, optional: true

  belongs_to :src_account, class_name: "Account"
  belongs_to :dest_account, class_name: "Account"

  belongs_to :currency
  belongs_to :fx_currency, class_name: "Currency", optional: true

  belongs_to :parent_transaction, class_name: "Transaction", optional: true
  has_many :child_transactions, class_name: "Transaction", foreign_key: "parent_transaction_id", dependent: :destroy

  belongs_to :merged_into, class_name: "Transaction", optional: true
  has_many :merged_sources, class_name: "Transaction", foreign_key: "merged_into_id", dependent: :destroy

  # Virtual form attributes — see TransactionsController#translate_form_params,
  # which converts them into src/dest before save.
  attr_accessor :anchor_account_id, :counterparty_account_id

  before_validation :assign_currency_from_dest_account, unless: :opening_balance?
  before_validation :assign_cleared_at_from_cleared, unless: :opening_balance?

  after_create :mark_parent_as_split, if: :parent_transaction_id?
  after_destroy :unmark_parent_if_last_child, if: :parent_transaction_id?
  after_save :transfer_account_balances
  after_destroy :reverse_account_balances
  after_commit :broadcast_sidebar_balances

  thread_mattr_accessor :sidebar_broadcast_collector, instance_accessor: false

  # Yields while collecting affected real-account IDs from every transaction
  # committed during the block (including cascading auto-merge / exclude
  # mutations), then broadcasts each account's sidebar balance once at block
  # end. Use this to aggregate broadcasts from bulk import jobs.
  def self.collecting_sidebar_broadcasts
    previous = sidebar_broadcast_collector
    self.sidebar_broadcast_collector = Set.new
    yield
    Account.real.where(id: sidebar_broadcast_collector).includes(:currency).find_each(&:broadcast_sidebar_update)
  ensure
    self.sidebar_broadcast_collector = previous
  end

  scope :opening_balances, -> { where(opening_balance: true) }
  scope :unmerged, -> { where(merged_into_id: nil) }
  scope :excluded, -> { where.not(excluded_at: nil) }
  scope :unexcluded, -> { where(excluded_at: nil) }

  def excluded?
    excluded_at.present?
  end

  validates :amount_minor, numericality: { allow_blank: true, unless: :amount_written? } # Blank is translated to 0
  validates :transacted_at, presence: true

  validate :src_account_accessible_to_user
  validate :dest_account_accessible_to_user

  validate :accounts_cannot_be_same, unless: -> { src_account_id.nil? || dest_account_id.nil? }
  validate :income_expense_must_pair_with_balance_sheet

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

  # The "anchor" is the side a human reads from: the balance-sheet account
  # (asset / liability / equity). Validation guarantees at least one side is
  # balance-sheet. For asset↔asset transfers, src wins.
  def anchor_account
    return nil if src_account.nil? && dest_account.nil?
    return src_account if src_account&.balance_sheet?
    dest_account
  end

  def counterparty_account
    anchor = anchor_account
    return nil if anchor.nil?
    anchor == src_account ? dest_account : src_account
  end

  # Signed amount from `account`'s perspective: negative when account is the
  # source (money leaving), positive when account is the destination.
  def signed_amount_minor_for(account)
    return nil if account.nil?
    account.id == src_account_id ? -amount_minor.to_i : amount_minor.to_i
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
      return if excluded?
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

    def broadcast_sidebar_balances
      ids = if destroyed?
        [ src_account_id_was, dest_account_id_was ]
      else
        [ src_account_id_before_last_save, dest_account_id_before_last_save,
          src_account_id, dest_account_id ]
      end.compact.uniq

      if (collector = self.class.sidebar_broadcast_collector)
        collector.merge(ids)
        return
      end

      Account.real.where(id: ids).includes(:currency).find_each(&:broadcast_sidebar_update)
    end

    def reverse_account_balances
      return if excluded?
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

    def income_expense_must_pair_with_balance_sheet
      return if src_account.nil? || dest_account.nil?

      if (src_account.expense? || src_account.revenue?) && !dest_account.balance_sheet?
        errors.add(:dest_account, "must be an asset, liability, or equity account")
      end

      if (dest_account.expense? || dest_account.revenue?) && !src_account.balance_sheet?
        errors.add(:src_account, "must be an asset, liability, or equity account")
      end
    end
end
