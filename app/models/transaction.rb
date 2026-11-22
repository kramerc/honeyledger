class Transaction < ApplicationRecord
  include Minorable
  attribute :amount_minor, MinorUnitsType.new
  attribute :fx_amount_minor, MinorUnitsType.new
  unminorable :amount_minor, with: :currency
  unminorable :fx_amount_minor, with: :fx_currency

  belongs_to :user
  has_many :transaction_sources, dependent: :destroy

  belongs_to :category, optional: true

  belongs_to :src_account, class_name: "Account"
  belongs_to :dest_account, class_name: "Account"

  belongs_to :currency
  belongs_to :fx_currency, class_name: "Currency", optional: true

  belongs_to :parent_transaction, class_name: "Transaction", optional: true
  has_many :child_transactions, class_name: "Transaction", foreign_key: "parent_transaction_id", dependent: :destroy

  belongs_to :merged_into, class_name: "Transaction", optional: true
  has_many :merged_sources, class_name: "Transaction", foreign_key: "merged_into_id", dependent: :destroy

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
    Account.in_sidebar.where(id: sidebar_broadcast_collector).includes(:currency).find_each(&:broadcast_sidebar_update)
  ensure
    self.sidebar_broadcast_collector = previous
  end

  scope :opening_balances, -> { where(opening_balance: true) }
  scope :unmerged, -> { where(merged_into_id: nil) }
  scope :excluded, -> { where.not(excluded_at: nil) }
  scope :unexcluded, -> { where(excluded_at: nil) }
  # Wallet network fees are never one leg of a transfer, so matching services skip them.
  scope :excluding_network_fees, -> {
    where.not(id: TransactionSource.where(sourceable_type: "Blockchain::Transaction", sourceable_id: Blockchain::Transaction.fee.select(:id)).select(:transaction_id))
  }

  def excluded?
    excluded_at.present?
  end

  # Whether this transaction may be excluded. Mirrors the guards in
  # Transaction::Exclude so the UI can gate the per-row link and bulk action.
  def excludable?
    transaction_sources.any? &&
      !excluded? &&
      !opening_balance? &&
      !merged_into_id? &&
      merged_sources.none? &&
      !split? &&
      !parent_transaction_id?
  end

  # Numericality checks the raw input, so non-integer or oversized strings fail here rather
  # than reaching the database. The blank check also reads the raw input: `allow_blank` would
  # test the cast value, which MinorUnitsType sets to nil for exactly the input to reject.
  validates :amount_minor, numericality: { only_integer: true, in: MinorUnitsType::RANGE },
    unless: -> { amount_written? || amount_minor_before_type_cast.blank? } # Blank is translated to 0
  validates :fx_amount_minor, numericality: { only_integer: true, in: MinorUnitsType::RANGE },
    unless: -> { fx_amount_written? || fx_amount_minor_before_type_cast.blank? }
  validate :raw_minor_amounts_cast_to_a_value
  validate :written_amounts_fit_minor_units
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
    [ src_account, dest_account ].find { |account| account&.real? }
  end

  # This transaction's own source rows with each sourceable preloaded. Reused for the
  # aggregated chips on the row and the per-origin chips in the "Merged from:" list.
  # Preload-safe: reuses the loaded proxy only when transaction_sources AND every
  # sourceable are already loaded; otherwise materializes via `.includes(:sourceable)`
  # so neither the caller's `.any?` nor the badge helper triggers an N+1.
  def own_badge_sources
    if transaction_sources.loaded? && transaction_sources.all? { |transaction_source| transaction_source.association(:sourceable).loaded? }
      transaction_sources.to_a
    else
      transaction_sources.includes(:sourceable).to_a
    end
  end

  # Source rows for this row's aggregated badges: this transaction's own plus those of
  # every merged origin. A merge result is created sourceless and inherits the aggregator
  # provenance only through the originals it absorbed (a re-imported CSV row also attaches
  # to the zeroed original, not the result — see Csv::ImportTransactionsJob #185). Dedup
  # and ordering are the badge helper's job. Preload-safe so single-row re-renders
  # (merge/unmerge/show) that skip the index preload don't N+1.
  def badge_transaction_sources
    own_badge_sources + merged_origins_for_badges.flat_map(&:own_badge_sources)
  end

  # Called when an importer attaches or re-encounters a source that does not write
  # canonical fields: a secondary source, or one Reconcile attached to an existing
  # transaction. Stamping synced_at with the source's own synced_at stops the importer's
  # `source.synced_at > ledger.synced_at` filter from re-matching the row.
  #
  # canonical_source is the transaction's first source before this one attached, or nil
  # when it had none. The stamp is skipped while that source holds a change its own
  # import has not applied yet: a refresh only advances a source's synced_at when its
  # data changes, so pushing synced_at past that change would hide it until the
  # canonical source next moves.
  def mark_synced_by_secondary_source!(canonical_source, sourceable)
    canonical_synced_at = canonical_source&.sourceable&.synced_at
    return if canonical_synced_at && canonical_synced_at > (synced_at || Time.at(0))

    update!(synced_at: [ synced_at, sourceable.synced_at || Time.current ].compact.max)
  end

  private

    # Merged origins with each origin's sources + sourceables loaded. Mirrors
    # own_badge_sources: reuses the loaded proxy only when merged_sources AND every
    # origin's nested transaction_sources/sourceables are already loaded (the index
    # preloads `merged_sources: { transaction_sources: :sourceable }`); otherwise
    # re-issues with `.includes` so a merged_sources collection that was loaded
    # without the nested data can't silently N+1 one query per origin.
    def merged_origins_for_badges
      fully_loaded = merged_sources.loaded? && merged_sources.all? do |origin|
        origin.transaction_sources.loaded? &&
          origin.transaction_sources.all? { |source| source.association(:sourceable).loaded? }
      end

      fully_loaded ? merged_sources : merged_sources.includes(transaction_sources: :sourceable).to_a
    end

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

      Account.in_sidebar.where(id: ids).includes(:currency).find_each(&:broadcast_sidebar_update)
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

    # Backstop for input numericality accepts but MinorUnitsType cannot cast, such as an integer
    # zero-padded past the type's length cap: without this it would be saved as nil.
    def raw_minor_amounts_cast_to_a_value
      { amount_minor: :amount_written?, fx_amount_minor: :fx_amount_written? }.each do |attribute, written|
        next if send(written) || errors.include?(attribute)
        next if send("#{attribute}_before_type_cast").blank? || !send(attribute).nil?

        errors.add(attribute, :invalid)
      end
    end

    # A decimal amount is converted to minor units only before save, so check here that the
    # converted value will fit the numeric(78, 0) column.
    def written_amounts_fit_minor_units
      { amount: :currency, fx_amount: :fx_currency }.each do |attribute, currency_attribute|
        next unless send("#{attribute}_written?")

        value = send(attribute)
        currency = send(currency_attribute)
        next if value.blank? || currency.nil? || errors.include?(attribute)

        minor = Minorable::Helpers.minor_from(value, currency.decimal_places)
        errors.add(attribute, "is too large") unless MinorUnitsType::RANGE.cover?(minor)
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
