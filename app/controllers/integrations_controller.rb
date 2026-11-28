class IntegrationsController < ApplicationController
  def show
    @simplefin_connection = current_user.simplefin_connection
    @lunchflow_connection = current_user.lunchflow_connection
    @simplefin_accounts = AggregatorLinkable.visible_accounts(@simplefin_connection)
    @lunchflow_accounts = AggregatorLinkable.visible_accounts(@lunchflow_connection)
    @blockchain_connections = current_user.blockchain_connections.order(:name, :id).to_a
    # Wallet accounts are always shown: an asset on chain never vanishes upstream
    # the way a bank aggregator account can, so a failed refresh must not hide it.
    @blockchain_accounts = Blockchain::Account.where(connection: @blockchain_connections)
      .includes(:connection, :ledger_accounts).sort_by { |account| [ account.connection.name.downcase, account.name.downcase ] }
    @linkable_accounts = current_user.accounts.linkable.order(:name)
  end
end
