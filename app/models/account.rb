class Account < ApplicationRecord
  belongs_to :user

  enum :kind, { asset: 0, liability: 1, equity: 2 }
end
