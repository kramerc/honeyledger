class TransactionSource < ApplicationRecord
  belongs_to :ledger_transaction, class_name: "Transaction", foreign_key: :transaction_id
  belongs_to :sourceable, polymorphic: true
end
