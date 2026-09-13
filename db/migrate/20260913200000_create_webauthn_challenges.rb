class CreateWebauthnChallenges < ActiveRecord::Migration[8.1]
  def change
    create_table :webauthn_challenges do |t|
      # Login challenges are issued before the user is known, so this is nullable.
      t.references :user, foreign_key: true
      t.string :purpose, default: "", null: false
      t.string :challenge, default: "", null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end
    add_index :webauthn_challenges, :expires_at
  end
end
