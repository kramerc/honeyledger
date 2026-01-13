class SimplefinConnection < ApplicationRecord
  belongs_to :user

  def client
    Simplefin.new(url: self.url)
  end
end
