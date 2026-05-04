class AccountSource < ApplicationRecord
  belongs_to :account
  belongs_to :sourceable, polymorphic: true
end
