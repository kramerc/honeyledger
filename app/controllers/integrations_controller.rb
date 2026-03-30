class IntegrationsController < ApplicationController
  before_action :authenticate_user!

  def show
    @simplefin_connection = current_user.simplefin_connection
    @lunchflow_connection = current_user.lunchflow_connection
    @simplefin_accounts = @simplefin_connection&.accounts&.includes(:ledger_account) || []
    @lunchflow_accounts = @lunchflow_connection&.accounts&.includes(:ledger_account) || []
    @linkable_accounts = current_user.accounts.linkable.unlinked.order(:name)
  end
end
