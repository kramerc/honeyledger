module AggregatorLinkable
  extend ActiveSupport::Concern

  included do
    has_many :account_sources, as: :sourceable, dependent: :destroy
    has_many :ledger_accounts, class_name: "Account", through: :account_sources, source: :account
    belongs_to :connection

    AggregatorLinkable.register(self)
  end

  # Singular accessor for callers that pre-date the M:M move. Aggregator accounts
  # are still single-linked at the controller level, so this is unambiguous in
  # practice; multi-link UI lands in a follow-up.
  def ledger_account
    ledger_accounts.first
  end

  # Use `any?` so callers that preloaded `:ledger_accounts` (e.g. the
  # integrations page) hit the loaded collection instead of issuing a
  # SELECT 1 per aggregator account.
  def linked?
    ledger_accounts.any?
  end

  def unlinked?
    !linked?
  end

  # The name an imported ledger account starts with on the new-account form.
  def suggested_ledger_account_name
    name
  end

  class_methods do
    def transaction_class
      "#{name.deconstantize}::Transaction".constantize
    end
  end

  class << self
    # A bank aggregator connection's accounts as the integrations page lists
    # them: linked ones always, unlinked ones only while the last refresh still
    # reported them, so an account the bank dropped stops cluttering the page.
    def visible_accounts(connection)
      return [] if connection.nil?

      threshold = connection.refreshed_at
      connection.accounts.includes(:ledger_accounts).select do |aggregator_account|
        aggregator_account.linked? || aggregator_account.current?(threshold)
      end.sort_by do |aggregator_account|
        [ aggregator_account.institution_name.to_s.downcase, aggregator_account.name.to_s.downcase ]
      end
    end

    # Store class names (stable strings) rather than class objects so the registry
    # stays correct across Zeitwerk reloads. After a reload, redefined classes
    # become new objects; if we held the old objects we'd either leak them or
    # generate stale references in queries. Resolving via `constantize` on each
    # read always returns the current class.
    def register(klass)
      registry_names << klass.name unless registry_names.include?(klass.name)
    end

    def registry
      registry_names.map(&:constantize)
    end

    private

      def registry_names
        @registry_names ||= []
      end
  end
end
