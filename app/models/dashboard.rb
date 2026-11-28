# What the signed-in dashboard shows one user: the integration problems and
# loose ends that need them, net worth per currency, and the latest activity.
class Dashboard
  include Rails.application.routes.url_helpers

  # Nothing refreshes connections on a schedule yet, so a connection left this
  # long is worth a nudge.
  STALE_AFTER = 3.days
  LUNCHFLOW_PROBLEM_STATUSES = {
    "ERROR" => "reports an error",
    "DISCONNECTED" => "is disconnected"
  }.freeze

  AttentionItem = Data.define(:message, :path, :severity) do
    def error?
      severity == :error
    end
  end

  NetWorthRow = Data.define(:currency, :assets_minor, :liabilities_minor) do
    # Liability balances are negative while money is owed, so they add.
    def net_minor
      assets_minor + liabilities_minor
    end
  end

  attr_reader :user

  def initialize(user)
    @user = user
  end

  # No balance-sheet account yet: the page offers first steps instead of
  # empty net worth and activity sections.
  def empty?
    !user.accounts.in_sidebar.exists?
  end

  # One row per currency. Currencies are never converted into one another.
  def net_worth
    @net_worth ||= begin
      sums = user.accounts.real.where(kind: %i[ asset liability ]).where.not(currency_id: nil)
        .group(:currency_id, :kind).sum(:balance_minor)
      currencies = Currency.where(id: sums.keys.map(&:first).uniq).index_by(&:id)

      currencies.values.sort_by(&:code).map do |currency|
        NetWorthRow.new(
          currency: currency,
          assets_minor: sums.fetch([ currency.id, "asset" ], 0).to_i,
          liabilities_minor: sums.fetch([ currency.id, "liability" ], 0).to_i
        )
      end
    end
  end

  # Errors first, then notices; each links to where it gets fixed.
  def attention_items
    @attention_items ||= begin
      items = simplefin_items + lunchflow_items + blockchain_items + unlinked_items
      errors, notices = items.partition(&:error?)
      errors + notices
    end
  end

  # The newest rows as the transactions index shows them.
  def recent_transactions(limit: 10)
    user.transactions.unmerged.unexcluded
      .includes(:src_account, :dest_account, :currency)
      .order(Transaction::Page::ORDER)
      .limit(limit)
  end

  private

    def simplefin_items
      connection = user.simplefin_connection
      return [] if connection.nil?

      items = []
      if connection.errlist.any?
        items << error("SimpleFIN reported #{pluralize(connection.errlist.size, "error")} on its last refresh")
      end
      items << stale_notice("SimpleFIN", connection) if stale?(connection)
      items
    end

    def lunchflow_items
      connection = user.lunchflow_connection
      return [] if connection.nil?

      items = []
      items << error("Lunch Flow: #{connection.error}") if connection.error.present?
      connection.accounts.where(status: LUNCHFLOW_PROBLEM_STATUSES.keys).includes(:ledger_accounts).order(:name).each do |lunchflow_account|
        next if lunchflow_account.unlinked?

        items << error("Lunch Flow account #{lunchflow_account.name} #{LUNCHFLOW_PROBLEM_STATUSES.fetch(lunchflow_account.status)}")
      end
      items << stale_notice("Lunch Flow", connection) if stale?(connection)
      items
    end

    # A wallet's error includes the Ethereum scanner's "Balance mismatch:" warning.
    def blockchain_items
      user.blockchain_connections.order(:name, :id).flat_map do |connection|
        items = []
        items << error("#{connection.name}: #{connection.error}") if connection.error.present?
        items << stale_notice(connection.name, connection) if stale?(connection)
        items
      end
    end

    # Counted the way the integrations page lists them, so the number matches.
    def unlinked_items
      count = [ user.simplefin_connection, user.lunchflow_connection ].sum do |connection|
        AggregatorLinkable.visible_accounts(connection).count(&:unlinked?)
      end
      count += user.blockchain_accounts.where.missing(:account_sources).count
      return [] if count.zero?

      verb = count == 1 ? "isn't" : "aren't"
      [ notice("#{pluralize(count, "aggregator account")} #{verb} linked to a ledger account") ]
    end

    def stale?(connection)
      connection.refreshed_at.nil? || connection.refreshed_at < STALE_AFTER.ago
    end

    def stale_notice(name, connection)
      if connection.refreshed_at.nil?
        notice("#{name} has never been refreshed")
      else
        days = ((Time.current - connection.refreshed_at) / 1.day).floor
        notice("#{name} was last refreshed #{pluralize(days, "day")} ago")
      end
    end

    def error(message)
      AttentionItem.new(message: message, path: integrations_path, severity: :error)
    end

    def notice(message)
      AttentionItem.new(message: message, path: integrations_path, severity: :notice)
    end

    def pluralize(count, word)
      "#{count} #{count == 1 ? word : word.pluralize}"
    end
end
