json.extract! transaction, :id, :parent_transaction_id, :category_id, :src_account_id, :dest_account_id, :description, :amount, :fx_amount, :fx_currency, :notes, :split, :created_at, :updated_at
json.url transaction_url(transaction, format: :json)
