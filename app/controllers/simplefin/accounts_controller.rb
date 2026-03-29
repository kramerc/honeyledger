class Simplefin::AccountsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_simplefin_account, only: [ :link, :unlink ]

  def link
    ledger_account_id = params.dig(:simplefin_account, :ledger_account_id)

    if ledger_account_id.blank?
      redirect_to integrations_path, alert: "Please select an account to link."
      return
    end

    # Verify the account belongs to the current user
    ledger_account = current_user.accounts.find_by(id: ledger_account_id)
    unless ledger_account
      redirect_to integrations_path, alert: "Account not found."
      return
    end

    if ledger_account.sourceable.present? && ledger_account.sourceable != @simplefin_account
      redirect_to integrations_path, alert: "Account is already linked to another integration."
      return
    end

    if @simplefin_account.linked? && @simplefin_account.ledger_account != ledger_account
      redirect_to integrations_path, alert: "SimpleFIN account is already linked to another account."
      return
    end

    if ledger_account.update(sourceable: @simplefin_account)
      redirect_to integrations_path, notice: "SimpleFIN account linked successfully."
    else
      redirect_to integrations_path, alert: "Failed to link SimpleFIN account: #{ledger_account.errors.full_messages.to_sentence}"
    end
  end

  def unlink
    ledger_account = @simplefin_account.ledger_account
    if ledger_account&.update(sourceable: nil)
      redirect_to integrations_path, notice: "SimpleFIN account unlinked successfully."
    else
      redirect_to integrations_path, alert: "Failed to unlink SimpleFIN account."
    end
  end

  private

    def set_simplefin_account
      @simplefin_account = current_user.simplefin_accounts.find(params.expect(:id))
    end
end
