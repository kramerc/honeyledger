require "test_helper"

class AggregatorLinkableTest < ActiveSupport::TestCase
  test "registry contains every aggregator account class" do
    assert_includes AggregatorLinkable.registry, Simplefin::Account
    assert_includes AggregatorLinkable.registry, Lunchflow::Account
  end

  test "transaction_class derives the namespaced transaction class" do
    assert_equal Simplefin::Transaction, Simplefin::Account.transaction_class
    assert_equal Lunchflow::Transaction, Lunchflow::Account.transaction_class
  end

  test "register is idempotent under repeated inclusion" do
    starting_size = AggregatorLinkable.registry.size

    AggregatorLinkable.register(Simplefin::Account)
    AggregatorLinkable.register(Simplefin::Account)
    AggregatorLinkable.register(Lunchflow::Account)

    assert_equal starting_size, AggregatorLinkable.registry.size
  end

  test "ledger_accounts through-association is wired against account_sources" do
    AggregatorLinkable.registry.each do |account_class|
      reflection = account_class.reflect_on_association(:ledger_accounts)
      assert_not_nil reflection, "#{account_class} should have a ledger_accounts association"
      assert_equal :account_sources, reflection.options[:through]
      assert_equal "Account", reflection.options[:class_name]
      assert_equal :account, reflection.options[:source]
    end
  end

  test "ledger_account singular shim returns first associated ledger account" do
    AggregatorLinkable.registry.each do |account_class|
      assert account_class.instance_methods.include?(:ledger_account), "#{account_class} should expose a ledger_account shim"
    end
  end

  test "registry resolves to the current class object even after the class is redefined" do
    # Simulates Zeitwerk reload: register a stand-in class under a name, then
    # redefine the class under the same name. Registry should resolve to the
    # current (redefined) class, not retain a reference to the old object.
    Object.const_set(:ReloadFixture, Class.new)
    AggregatorLinkable.register(ReloadFixture)
    original = ReloadFixture
    Object.send(:remove_const, :ReloadFixture)
    Object.const_set(:ReloadFixture, Class.new)

    resolved = AggregatorLinkable.registry.find { |klass| klass.name == "ReloadFixture" }
    assert_equal ReloadFixture, resolved
    refute_same original, resolved
  ensure
    AggregatorLinkable.send(:registry_names).delete("ReloadFixture")
    Object.send(:remove_const, :ReloadFixture) if defined?(ReloadFixture)
  end
end
