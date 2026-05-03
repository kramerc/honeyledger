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

  def linked?
    ledger_accounts.exists?
  end

  def unlinked?
    !linked?
  end

  class_methods do
    def transaction_class
      "#{name.deconstantize}::Transaction".constantize
    end
  end

  class << self
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
