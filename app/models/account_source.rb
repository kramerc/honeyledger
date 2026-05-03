class AccountSource < ApplicationRecord
  belongs_to :account
  belongs_to :sourceable, polymorphic: true

  after_create_commit :enqueue_source_import

  private

    def enqueue_source_import
      case sourceable
      when Simplefin::Account
        Simplefin::ImportTransactionsJob.perform_later(simplefin_account_id: sourceable_id)
      when Lunchflow::Account
        Lunchflow::ImportTransactionsJob.perform_later(lunchflow_account_id: sourceable_id)
      end
    end
end
