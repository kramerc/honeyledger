module ApplicationHelper
  def prefix_active?(current_path, target_path)
    current_path.present? && target_path.present? &&
      (current_path == target_path || current_path.start_with?("#{target_path}/"))
  end

  def source_badge_label(sourceable)
    case sourceable
    when Simplefin::Account, Simplefin::Transaction then "SimpleFIN"
    when Lunchflow::Account, Lunchflow::Transaction then "Lunch Flow"
    when Csv::Transaction then "CSV"
    else sourceable.class.name
    end
  end

  def source_badge_modifier(sourceable)
    case sourceable
    when Simplefin::Account, Simplefin::Transaction then "source-badge--simplefin"
    when Lunchflow::Account, Lunchflow::Transaction then "source-badge--lunchflow"
    when Csv::Transaction then "source-badge--csv"
    end
  end

  # Sort rank for source badges, matching the aggregator order on the integrations
  # page (SimpleFIN, then Lunch Flow, then CSV) rather than sorting alphabetically.
  def source_badge_order(sourceable)
    case sourceable
    when Simplefin::Account, Simplefin::Transaction then 0
    when Lunchflow::Account, Lunchflow::Transaction then 1
    when Csv::Transaction then 2
    else 3
    end
  end

  # Caller is responsible for passing a collection where each TransactionSource's
  # sourceable is already loaded (e.g., array from `includes(:sourceable)`).
  # An unloaded relation will N+1 on the per-source sourceable access below.
  #
  # Sorted by source_badge_order first so chips always render in aggregator order
  # (SimpleFIN, Lunch Flow, CSV) regardless of input order — merge results concatenate
  # own and origin sources, so input order is otherwise non-deterministic.
  #
  # Deduped by label so a ledger transaction carrying several sources of the same
  # type renders a single chip. A CSV that overlaps a prior import for the same
  # account attaches a second Csv::Transaction source (no stable external id, so
  # every import creates fresh rows) — without this, that shows as repeated "CSV"
  # chips (#151). Sorting before uniq is safe: equal order keys only occur for
  # same-label records, which uniq collapses anyway.
  def transaction_source_badges(sources)
    badges = sources
      .map(&:sourceable)
      .sort_by { |sourceable| source_badge_order(sourceable) }
      .uniq { |sourceable| source_badge_label(sourceable) }
      .map do |sourceable|
        classes = [ "source-badge", source_badge_modifier(sourceable) ].compact.join(" ")
        tag.span(source_badge_label(sourceable), class: classes)
      end
    safe_join(badges, " ")
  end

  def nav_link_to(name, url, options = {})
    active = options.delete(:active)

    is_active = case active
    when :prefix
      prefix_active?(request.path, url)
    else
      current_page?(url)
    end

    if is_active
      options[:class] = class_names(options[:class], "active")
    end

    link_to name, url, options
  end
end
