class DropLegacySourceableColumns < ActiveRecord::Migration[8.1]
  def up
    remove_index :accounts, name: "index_accounts_on_sourceable", column: [ :sourceable_type, :sourceable_id ], unique: true
    remove_column :accounts, :sourceable_id, :bigint
    remove_column :accounts, :sourceable_type, :string

    remove_index :transactions, name: "index_transactions_on_sourceable", column: [ :sourceable_type, :sourceable_id ]
    remove_column :transactions, :sourceable_id, :bigint
    remove_column :transactions, :sourceable_type, :string
  end

  # On rollback, recreate the legacy columns AND repopulate them from the join
  # tables so the previous release's code still sees its own data. Without the
  # data-copy step, `bin/rails db:rollback` would leave every account/transaction
  # looking unlinked even though the join-table rows are still there.
  #
  # Multi-source ledger accounts/transactions (possible in PR 3 once the
  # single-link controller guard is dropped) are condensed back to one source
  # per row using DISTINCT ON ordered by created_at, id — picking the first
  # writer, which matches the canonical-source rule the import path uses.
  def down
    add_column :accounts, :sourceable_type, :string
    add_column :accounts, :sourceable_id, :bigint

    execute <<~SQL
      UPDATE accounts a
      SET sourceable_type = s.sourceable_type,
          sourceable_id = s.sourceable_id
      FROM (
        SELECT DISTINCT ON (account_id) account_id, sourceable_type, sourceable_id
        FROM account_sources
        ORDER BY account_id, created_at, id
      ) s
      WHERE a.id = s.account_id
    SQL

    add_index :accounts, [ :sourceable_type, :sourceable_id ], unique: true, name: "index_accounts_on_sourceable"

    add_column :transactions, :sourceable_type, :string
    add_column :transactions, :sourceable_id, :bigint

    execute <<~SQL
      UPDATE transactions t
      SET sourceable_type = s.sourceable_type,
          sourceable_id = s.sourceable_id
      FROM (
        SELECT DISTINCT ON (transaction_id) transaction_id, sourceable_type, sourceable_id
        FROM transaction_sources
        ORDER BY transaction_id, created_at, id
      ) s
      WHERE t.id = s.transaction_id
    SQL

    add_index :transactions, [ :sourceable_type, :sourceable_id ], name: "index_transactions_on_sourceable"
  end
end
