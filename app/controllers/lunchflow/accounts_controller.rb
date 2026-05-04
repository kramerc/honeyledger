class Lunchflow::AccountsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_lunchflow_account, only: [ :link, :unlink ]

  def link
    ledger_account_id = params.dig(:lunchflow_account, :ledger_account_id)

    if ledger_account_id.blank?
      redirect_to integrations_path, alert: "Please select an account to link."
      return
    end

    ledger_account = current_user.accounts.find_by(id: ledger_account_id)
    unless ledger_account
      redirect_to integrations_path, alert: "Account not found."
      return
    end

    if ledger_account.account_sources.where.not(sourceable: @lunchflow_account).exists?
      redirect_to integrations_path, alert: "Account is already linked to another integration."
      return
    end

    if @lunchflow_account.linked? && @lunchflow_account.ledger_account != ledger_account
      redirect_to integrations_path, alert: "Lunch Flow account is already linked to another account."
      return
    end

    AccountSource::Attach.call(account: ledger_account, sourceable: @lunchflow_account)
    redirect_to integrations_path, notice: "Lunch Flow account linked successfully."
  rescue AccountSource::Attach::MismatchedAccount
    redirect_to integrations_path, alert: "Lunch Flow account is already linked to another account."
  end

  def unlink
    @lunchflow_account.account_sources.destroy_all
    redirect_to integrations_path, notice: "Lunch Flow account unlinked successfully."
  end

  private

    def set_lunchflow_account
      @lunchflow_account = current_user.lunchflow_accounts.find(params.expect(:id))
    end
end
