class SimplefinAccountsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_simplefin_account, only: [ :link, :unlink ]

  def link
    if simplefin_account_params[:account_id].blank?
      redirect_to simplefin_connection_path, alert: "Please select an account to link."
      return
    end

    if @simplefin_account.update(simplefin_account_params)
      redirect_to simplefin_connection_path, notice: "SimpleFIN account linked successfully."
    else
      redirect_to simplefin_connection_path, alert: "Failed to link SimpleFIN account: #{@simplefin_account.errors.full_messages.to_sentence}"
    end
  end

  def unlink
    @simplefin_account.update(account_id: nil)
    redirect_to simplefin_connection_path, notice: "SimpleFIN account unlinked successfully."
  end

  private
    def set_simplefin_account
      @simplefin_account = current_user.simplefin_accounts.find(params[:id])
    end

    def simplefin_account_params
      params.require(:simplefin_account).permit(:account_id)
    end
end
