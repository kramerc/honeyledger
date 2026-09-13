class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :passkeys, dependent: :destroy

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: /\A[^@\s]+@[^@\s]+\z/ }
  # Six characters matches the Devise minimum this app started with, so no
  # existing user is invalidated. has_secure_password enforces the 72-byte
  # bcrypt ceiling and presence on create.
  validates :password, length: { minimum: 6 }, allow_nil: true

  # Opaque handle authenticators store alongside a passkey; never the email.
  before_create { self.webauthn_id ||= WebAuthn.generate_user_id }

  has_many :accounts, dependent: :destroy
  has_many :import_rules, dependent: :destroy
  has_many :categories, dependent: :destroy
  has_many :transactions, dependent: :destroy

  has_one :simplefin_connection, class_name: "Simplefin::Connection", dependent: :destroy
  has_many :simplefin_accounts, class_name: "Simplefin::Account", through: :simplefin_connection, source: :accounts

  has_one :lunchflow_connection, class_name: "Lunchflow::Connection", dependent: :destroy
  has_many :lunchflow_accounts, class_name: "Lunchflow::Account", through: :lunchflow_connection, source: :accounts

  has_many :csv_imports, class_name: "Csv::Import", dependent: :destroy
end
