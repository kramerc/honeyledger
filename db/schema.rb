# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_13_101743) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "currency_id", null: false
    t.integer "kind"
    t.string "name"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["currency_id"], name: "index_accounts_on_currency_id"
    t.index ["user_id", "kind"], name: "index_accounts_on_user_id_and_kind"
    t.index ["user_id"], name: "index_accounts_on_user_id"
  end

  create_table "categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "icon"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "currencies", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", limit: 10, null: false
    t.datetime "created_at", null: false
    t.integer "decimal_places", default: 2, null: false
    t.integer "kind", default: 0, null: false
    t.string "name", null: false
    t.string "symbol", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_currencies_on_code", unique: true
    t.index ["kind"], name: "index_currencies_on_kind"
  end

  create_table "simplefin_accounts", force: :cascade do |t|
    t.bigint "account_id"
    t.string "available_balance"
    t.string "balance"
    t.datetime "balance_date", precision: nil
    t.datetime "created_at", null: false
    t.string "currency"
    t.jsonb "extra"
    t.string "name"
    t.jsonb "org"
    t.string "remote_id"
    t.bigint "simplefin_connection_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_simplefin_accounts_on_account_id", unique: true
    t.index ["simplefin_connection_id"], name: "index_simplefin_accounts_on_simplefin_connection_id"
  end

  create_table "simplefin_connections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "refreshed_at", precision: nil
    t.datetime "updated_at", null: false
    t.string "url"
    t.bigint "user_id", null: false
    t.index ["refreshed_at"], name: "index_simplefin_connections_on_refreshed_at"
    t.index ["user_id"], name: "index_simplefin_connections_on_user_id", unique: true
  end

  create_table "simplefin_transactions", force: :cascade do |t|
    t.string "amount"
    t.datetime "created_at", null: false
    t.string "description"
    t.jsonb "extra"
    t.boolean "pending"
    t.datetime "posted", precision: nil
    t.string "remote_id"
    t.bigint "simplefin_account_id", null: false
    t.datetime "synced_at", precision: nil
    t.datetime "transacted_at", precision: nil
    t.datetime "updated_at", null: false
    t.index ["simplefin_account_id"], name: "index_simplefin_transactions_on_simplefin_account_id"
    t.index ["synced_at"], name: "index_simplefin_transactions_on_synced_at"
  end

  create_table "transactions", force: :cascade do |t|
    t.integer "amount_minor", default: 0, null: false
    t.bigint "category_id"
    t.datetime "cleared_at", precision: nil
    t.datetime "created_at", null: false
    t.bigint "currency_id", null: false
    t.string "description", default: "", null: false
    t.bigint "dest_account_id", null: false
    t.integer "fx_amount_minor"
    t.bigint "fx_currency_id"
    t.text "notes", default: "", null: false
    t.boolean "opening_balance", default: false, null: false
    t.bigint "parent_transaction_id"
    t.datetime "reconciled_at", precision: nil
    t.bigint "sourceable_id"
    t.string "sourceable_type"
    t.boolean "split", default: false, null: false
    t.bigint "src_account_id", null: false
    t.datetime "synced_at", precision: nil
    t.datetime "transacted_at", precision: nil, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["currency_id"], name: "index_transactions_on_currency_id"
    t.index ["dest_account_id"], name: "index_transactions_on_dest_account_id"
    t.index ["fx_currency_id"], name: "index_transactions_on_fx_currency_id"
    t.index ["parent_transaction_id"], name: "index_transactions_on_parent_transaction_id"
    t.index ["sourceable_type", "sourceable_id"], name: "index_transactions_on_sourceable"
    t.index ["src_account_id"], name: "index_transactions_on_src_account_id"
    t.index ["user_id", "split"], name: "index_transactions_on_user_id_and_split"
    t.index ["user_id", "transacted_at"], name: "index_transactions_on_user_id_and_transacted_at"
    t.index ["user_id"], name: "index_transactions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "accounts", "currencies"
  add_foreign_key "accounts", "users"
  add_foreign_key "simplefin_accounts", "accounts"
  add_foreign_key "simplefin_accounts", "simplefin_connections"
  add_foreign_key "simplefin_connections", "users"
  add_foreign_key "simplefin_transactions", "simplefin_accounts"
  add_foreign_key "transactions", "accounts", column: "dest_account_id"
  add_foreign_key "transactions", "accounts", column: "src_account_id"
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "currencies"
  add_foreign_key "transactions", "currencies", column: "fx_currency_id"
  add_foreign_key "transactions", "transactions", column: "parent_transaction_id"
  add_foreign_key "transactions", "users"
end
