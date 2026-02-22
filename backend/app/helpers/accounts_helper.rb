module AccountsHelper
  # Build <option> tags with data-kind and data-currency attributes for account selects.
  def account_options_with_kind(accounts, selected_id, prompt: nil)
    opts = []
    opts << content_tag(:option, html_escape(prompt), value: "") if prompt
    accounts.each do |account|
      opts << content_tag(:option, html_escape(account.name),
        value: account.id,
        selected: (account.id == selected_id ? "selected" : nil),
        data: { kind: account.kind, currency: account.currency.code })
    end
    safe_join(opts)
  end
end
