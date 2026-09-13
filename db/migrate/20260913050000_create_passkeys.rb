class CreatePasskeys < ActiveRecord::Migration[8.1]
  def up
    create_table :passkeys do |t|
      t.references :user, null: false, foreign_key: true
      # The credential id issued by the authenticator (base64url). It is unique
      # by definition, so unlike other string columns it cannot default to "".
      t.string :external_id, null: false
      t.text :public_key, default: "", null: false
      t.bigint :sign_count, default: 0, null: false
      t.string :nickname, default: "", null: false
      t.datetime :last_used_at

      t.timestamps
    end
    add_index :passkeys, :external_id, unique: true

    # Opaque per-user handle sent to authenticators as the WebAuthn user id.
    # Random and unique, so existing rows are backfilled rather than defaulted.
    add_column :users, :webauthn_id, :string
    select_values("SELECT id FROM users").each do |user_id|
      execute "UPDATE users SET webauthn_id = #{quote(WebAuthn.generate_user_id)} WHERE id = #{quote(user_id)}"
    end
    change_column_null :users, :webauthn_id, false
    add_index :users, :webauthn_id, unique: true
  end

  def down
    remove_index :users, :webauthn_id
    remove_column :users, :webauthn_id
    drop_table :passkeys
  end
end
