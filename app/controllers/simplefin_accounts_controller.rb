class SimplefinAccountsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_simplefin_account, only: [ :link, :unlink ]

  def link
    account_id = params.dig(:simplefin_account, :account_id)

    if account_id.blank?
      redirect_to simplefin_connection_path, alert: "Please select an account to link."
      return
    end

    # Verify the account belongs to the current user
    account = current_user.accounts.find_by(id: account_id)
    unless account
      redirect_to simplefin_connection_path, alert: "Account not found."
      return
    end

    if @simplefin_account.update(account: account)
      redirect_to simplefin_connection_path, notice: "SimpleFIN account linked successfully."
    else
      redirect_to simplefin_connection_path, alert: "Failed to link SimpleFIN account: #{@simplefin_account.errors.full_messages.to_sentence}"
    end
  end

  def unlink
    if @simplefin_account.update(account_id: nil)
      redirect_to simplefin_connection_path, notice: "SimpleFIN account unlinked successfully."
    else
      redirect_to simplefin_connection_path, alert: "Failed to unlink SimpleFIN account: #{@simplefin_account.errors.full_messages.to_sentence}"
    end
  end

  private
    def set_simplefin_account
      @simplefin_account = current_user.simplefin_accounts.find(params[:id])
    end
end
