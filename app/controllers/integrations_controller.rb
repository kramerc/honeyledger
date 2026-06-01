class IntegrationsController < ApplicationController
  before_action :authenticate_user!

  def show
    @simplefin_connection = current_user.simplefin_connection
    @lunchflow_connection = current_user.lunchflow_connection
    @simplefin_accounts = visible_aggregator_accounts(@simplefin_connection)
    @lunchflow_accounts = visible_aggregator_accounts(@lunchflow_connection)
    @linkable_accounts = current_user.accounts.linkable.order(:name)
  end

  private

    def visible_aggregator_accounts(connection)
      return [] if connection.nil?

      threshold = connection.refreshed_at
      connection.accounts.includes(:ledger_accounts).select do |aggregator_account|
        aggregator_account.linked? || aggregator_account.current?(threshold)
      end.sort_by do |aggregator_account|
        [ aggregator_account.institution_name.to_s.downcase, aggregator_account.name.to_s.downcase ]
      end
    end
end
