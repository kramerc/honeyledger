module AccountsHelper
  def account_options(accounts)
    accounts.map do |account|
      [ account.name, account.id, { data: { currency: account.currency.code, kind: account.kind } } ]
    end
  end

  def grouped_account_options_for_select(accounts, groups, selected_key: nil)
    accounts_by_kind = accounts.group_by(&:kind)

    # Remove groups that don't have any accounts
    groups = groups.reject { |kind| accounts_by_kind[kind.to_s].blank? }

    grouped_options = groups.map do |kind|
      [ kind.to_s.titleize, account_options(accounts_by_kind[kind.to_s] || []) ]
    end
    grouped_options_for_select(grouped_options, selected_key)
  end
end
