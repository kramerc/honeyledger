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
    def register(klass)
      registry << klass unless registry.include?(klass)
    end

    def registry
      @registry ||= []
    end
  end
end
