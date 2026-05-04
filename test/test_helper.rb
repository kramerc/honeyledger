require "simplecov"
SimpleCov.start "rails"

require "simplecov-cobertura"
SimpleCov.formatters = [
  SimpleCov::Formatter::CoberturaFormatter,
  SimpleCov::Formatter::HTMLFormatter
]

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
require "minitest/stub_any_instance"
require "turbo/broadcastable/test_helper"
Minitest.load_plugins

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    # Commented out to avoid issues with SimpleCov
    # parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include Turbo::Broadcastable::TestHelper

    # Build a ledger Transaction and attach an aggregator transaction as its source
    # in one step. Pass the aggregator transaction as `sourceable:` and the rest of
    # the Transaction attributes as keyword args.
    def create_sourced_transaction(sourceable:, **attrs)
      Transaction.create!(**attrs).tap do |txn|
        TransactionSource.create!(ledger_transaction: txn, sourceable: sourceable)
      end
    end
  end
end
