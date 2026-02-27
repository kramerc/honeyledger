class Simplefin::Account < ApplicationRecord
  belongs_to :ledger_account, class_name: "Account", optional: true
  belongs_to :connection
  has_many :transactions, dependent: :destroy

  validates :ledger_account_id, uniqueness: true, allow_nil: true

  after_update_commit :enqueue_import, if: :saved_change_to_ledger_account_id?

  def linked?
    ledger_account_id.present?
  end

  def unlinked?
    ledger_account_id.blank?
  end

  def enqueue_import
    TransactionImportJob.perform_later(simplefin_account_id: id)
  end
end
