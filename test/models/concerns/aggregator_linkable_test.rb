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

  test "ledger_account association is wired with the polymorphic sourceable name" do
    AggregatorLinkable.registry.each do |account_class|
      reflection = account_class.reflect_on_association(:ledger_account)
      assert_not_nil reflection, "#{account_class} should have a ledger_account association"
      assert_equal :sourceable, reflection.options[:as]
      assert_equal "Account", reflection.options[:class_name]
      assert_equal :nullify, reflection.options[:dependent]
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
