module AccountsHelper
  def account_nav_link_to(account)
    target = account_transactions_path(account)

    balance_minor = account.balance_minor
    balance_span = if balance_minor
      balance = amount_to_currency(balance_minor, account.currency)
      balance_class = balance_minor >= 0 ? "account__balance account__balance--positive" : "account__balance account__balance--negative"
      content_tag(:span, balance, class: balance_class)
    end

    nav_link_to target do
      content_tag(:span, account.name, class: "account__name") + balance_span.to_s
    end
  end

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
