class SimplefinAccount < ApplicationRecord
  belongs_to :account, optional: true
  belongs_to :simplefin_connection
  has_many :transactions, class_name: "SimplefinTransaction", dependent: :destroy

  validates :account_id, uniqueness: true, allow_nil: true

  after_update :enqueue_import!, if: :saved_change_to_account_id?

  def linked?
    account_id.present?
  end

  def unlinked?
    account_id.blank?
  end

  def enqueue_import!
    TransactionImportJob.perform_later(simplefin_account_id: id)
  end
end
