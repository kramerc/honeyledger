# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Fiat currencies (ISO 4217)
# TODO: Seed if we can automate this with an external data source
Currency.find_or_create_by!(code: "USD") do |c|
  c.name = "US Dollar"
  c.symbol = "$"
  c.kind = 0  # fiat
  c.decimal_places = 2
  c.active = true
end

Currency.find_or_create_by!(code: "EUR") do |c|
  c.name = "Euro"
  c.symbol = "€"
  c.kind = 0
  c.decimal_places = 2
  c.active = true
end

Currency.find_or_create_by!(code: "GBP") do |c|
  c.name = "British Pound"
  c.symbol = "£"
  c.kind = 0
  c.decimal_places = 2
  c.active = true
end

Currency.find_or_create_by!(code: "JPY") do |c|
  c.name = "Japanese Yen"
  c.symbol = "¥"
  c.kind = 0
  c.decimal_places = 0
  c.active = true
end

# Cryptocurrencies
Currency.find_or_create_by!(code: "BTC") do |c|
  c.name = "Bitcoin"
  c.symbol = "₿"
  c.kind = 1  # crypto
  c.decimal_places = 8
  c.active = true
end

Currency.find_or_create_by!(code: "ETH") do |c|
  c.name = "Ethereum"
  c.symbol = "Ξ"
  c.kind = 1
  c.decimal_places = 18
  c.active = true
end

Currency.find_or_create_by!(code: "USDT") do |c|
  c.name = "Tether"
  c.symbol = "₮"
  c.kind = 1
  c.decimal_places = 6
  c.active = true
end

Currency.find_or_create_by!(code: "USDC") do |c|
  c.name = "USD Coin"
  c.symbol = "$"
  c.kind = 1
  c.decimal_places = 6
  c.active = true
end
