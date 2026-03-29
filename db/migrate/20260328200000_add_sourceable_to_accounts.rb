class AddSourceableToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_reference :accounts, :sourceable, polymorphic: true, index: { unique: true }

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE accounts
          SET sourceable_type = 'Simplefin::Account',
              sourceable_id = simplefin_accounts.id
          FROM simplefin_accounts
          WHERE simplefin_accounts.ledger_account_id = accounts.id
        SQL
      end

      dir.down do
        execute <<~SQL
          UPDATE simplefin_accounts
          SET ledger_account_id = accounts.id
          FROM accounts
          WHERE accounts.sourceable_type = 'Simplefin::Account'
            AND accounts.sourceable_id = simplefin_accounts.id
        SQL
      end
    end

    remove_reference :simplefin_accounts, :ledger_account, foreign_key: { to_table: :accounts }, index: { unique: true }
  end
end
