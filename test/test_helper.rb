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
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/passkey_test_helper"
require_relative "test_helpers/evm_explorer_test_helper"
require "minitest/mock"
require "minitest/stub_any_instance"
require "turbo/broadcastable/test_helper"
Minitest.load_plugins

module ActiveSupport
  class TestCase
    # Each worker process gets its own test database (Rails appends _<n> to the
    # name). System test workers also get their own Capybara server and Chrome,
    # hence the cap. Runs under Rails' threshold of 50 tests stay serial, and
    # PARALLEL_WORKERS=1 forces a serial run when debugging. SimpleCov needs no
    # hook: it tracks the forked workers and merges their coverage itself.
    parallelize(workers: ENV.fetch("PARALLEL_WORKERS", [ Etc.nprocessors, 8 ].min).to_i)

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
