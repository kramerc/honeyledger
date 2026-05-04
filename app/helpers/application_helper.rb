module ApplicationHelper
  def prefix_active?(current_path, target_path)
    current_path.present? && target_path.present? &&
      (current_path == target_path || current_path.start_with?("#{target_path}/"))
  end

  def source_badge_label(sourceable)
    case sourceable
    when Simplefin::Account, Simplefin::Transaction then "SimpleFIN"
    when Lunchflow::Account, Lunchflow::Transaction then "Lunch Flow"
    else sourceable.class.name
    end
  end

  # Caller is responsible for passing a collection where each TransactionSource's
  # sourceable is already loaded (e.g., array from `includes(:sourceable)`).
  # An unloaded relation will N+1 on the per-source sourceable access below.
  def transaction_source_badges(sources)
    badges = sources.map do |source|
      tag.span(source_badge_label(source.sourceable), class: "source-badge")
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
