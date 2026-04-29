module AccountsHelper
  def account_sidebar_link(account, active_path: nil)
    target = account_transactions_path(account)
    is_active = prefix_active?(active_path, account_path(account))

    link_to target,
            id: dom_id(account, :sidebar_link),
            class: ("active" if is_active),
            data: {
              controller: "inline-rename",
              inline_rename_url_value: account_path(account)
            } do
      render("accounts/sidebar_link_content", account: account)
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
