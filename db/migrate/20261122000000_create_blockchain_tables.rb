class CreateBlockchainTables < ActiveRecord::Migration[8.1]
  def change
    # One row per tracked wallet: a single address or an extended public key.
    create_table :blockchain_connections do |t|
      t.references :user, null: false, foreign_key: true
      t.string :chain, null: false, default: ""
      t.string :name, null: false, default: ""
      t.string :identifier, null: false, default: ""
      t.string :error
      t.timestamp :refreshed_at

      t.timestamps
    end
    add_index :blockchain_connections, [ :user_id, :chain, :identifier ], unique: true
    add_index :blockchain_connections, :refreshed_at

    # Addresses derived from an extended key, cached so a refresh resumes the
    # gap-limit scan from the last used index instead of re-deriving.
    create_table :blockchain_addresses do |t|
      t.references :connection, null: false, foreign_key: { to_table: :blockchain_connections }
      t.integer :branch, null: false
      t.integer :index, null: false
      t.string :address, null: false, default: ""
      t.boolean :used, null: false, default: false

      t.timestamps
    end
    add_index :blockchain_addresses, [ :connection_id, :address ], unique: true
    add_index :blockchain_addresses, [ :connection_id, :branch, :index ], unique: true

    # One row per asset held by a wallet (native coin for now).
    create_table :blockchain_accounts do |t|
      t.references :connection, null: false, foreign_key: { to_table: :blockchain_connections }
      t.string :remote_id, null: false, default: ""
      t.string :name, null: false, default: ""
      t.string :currency, null: false, default: ""
      t.string :balance
      t.datetime :last_seen_at
      t.datetime :balance_changed_at

      t.timestamps
    end
    add_index :blockchain_accounts, [ :connection_id, :remote_id ], unique: true

    # Wallet-relative movements: one transfer row per on-chain transaction, plus
    # a fee row ("<txid>:fee") when the wallet paid the network fee.
    create_table :blockchain_transactions do |t|
      t.references :account, null: false, foreign_key: { to_table: :blockchain_accounts }
      t.string :remote_id, null: false, default: ""
      t.string :txid, null: false, default: ""
      t.string :kind, null: false, default: "transfer"
      t.string :amount, null: false, default: "0"
      t.string :counterparty
      t.integer :block_height
      t.datetime :transacted_at
      t.boolean :confirmed, null: false, default: false
      t.timestamp :synced_at

      t.timestamps
    end
    add_index :blockchain_transactions, [ :account_id, :remote_id ], unique: true
    add_index :blockchain_transactions, :txid
    add_index :blockchain_transactions, :synced_at
  end
end
