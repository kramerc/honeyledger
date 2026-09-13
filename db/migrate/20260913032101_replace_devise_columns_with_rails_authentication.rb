class ReplaceDeviseColumnsWithRailsAuthentication < ActiveRecord::Migration[8.1]
  def change
    # Devise stored plain bcrypt digests (no pepper), which is exactly what
    # has_secure_password reads, so existing passwords keep working after the rename.
    rename_column :users, :encrypted_password, :password_digest

    # Devise recoverable / rememberable / trackable columns. Nothing reads them:
    # password reset now goes through generates_token_for and sessions live in
    # their own table.
    remove_index :users, :reset_password_token, unique: true
    remove_column :users, :reset_password_token, :string
    remove_column :users, :reset_password_sent_at, :datetime
    remove_column :users, :remember_created_at, :datetime
    remove_column :users, :sign_in_count, :integer, default: 0, null: false
    remove_column :users, :current_sign_in_at, :datetime
    remove_column :users, :last_sign_in_at, :datetime
    remove_column :users, :current_sign_in_ip, :string
    remove_column :users, :last_sign_in_ip, :string

    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ip_address, default: "", null: false
      t.string :user_agent, default: "", null: false

      t.timestamps
    end
  end
end
