module AggregatorLinkable
  extend ActiveSupport::Concern

  included do
    has_one :ledger_account, class_name: "Account", as: :sourceable, dependent: :nullify
    belongs_to :connection

    AggregatorLinkable.register(self)
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
