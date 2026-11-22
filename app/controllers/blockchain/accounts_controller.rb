class Blockchain::AccountsController < ApplicationController
  before_action :set_blockchain_account, only: [ :link, :unlink ]

  def link
    ledger_account_id = params.dig(:blockchain_account, :ledger_account_id)

    if ledger_account_id.blank?
      redirect_to integrations_path, alert: "Please select an account to link."
      return
    end

    ledger_account = current_user.accounts.find_by(id: ledger_account_id)
    unless ledger_account
      redirect_to integrations_path, alert: "Account not found."
      return
    end

    if @blockchain_account.linked? && @blockchain_account.ledger_account != ledger_account
      redirect_to integrations_path, alert: "Wallet account is already linked to another account."
      return
    end

    AccountSource::Attach.call(account: ledger_account, sourceable: @blockchain_account)
    redirect_to integrations_path, notice: "Wallet account linked successfully."
  rescue AccountSource::Attach::MismatchedAccount
    redirect_to integrations_path, alert: "Wallet account is already linked to another account."
  end

  def unlink
    @blockchain_account.account_sources.destroy_all
    redirect_back_or_to integrations_path, notice: "Wallet account unlinked successfully."
  end

  private

    def set_blockchain_account
      @blockchain_account = current_user.blockchain_accounts.find(params.expect(:id))
    end
end
