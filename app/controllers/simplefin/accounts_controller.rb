class Simplefin::AccountsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_simplefin_account, only: [ :link, :unlink ]

  def link
    ledger_account_id = params.dig(:simplefin_account, :ledger_account_id)

    if ledger_account_id.blank?
      redirect_to integrations_path, alert: "Please select an account to link."
      return
    end

    ledger_account = current_user.accounts.find_by(id: ledger_account_id)
    unless ledger_account
      redirect_to integrations_path, alert: "Account not found."
      return
    end

    if ledger_account.account_sources.where.not(sourceable: @simplefin_account).exists?
      redirect_to integrations_path, alert: "Account is already linked to another integration."
      return
    end

    if @simplefin_account.linked? && @simplefin_account.ledger_account != ledger_account
      redirect_to integrations_path, alert: "SimpleFIN account is already linked to another account."
      return
    end

    AccountSource::Attach.call(account: ledger_account, sourceable: @simplefin_account)
    redirect_to integrations_path, notice: "SimpleFIN account linked successfully."
  end

  def unlink
    @simplefin_account.account_sources.destroy_all
    redirect_to integrations_path, notice: "SimpleFIN account unlinked successfully."
  end

  private

    def set_simplefin_account
      @simplefin_account = current_user.simplefin_accounts.find(params.expect(:id))
    end
end
