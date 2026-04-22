module ApplicationHelper
  def prefix_active?(current_path, target_path)
    current_path.present? && target_path.present? &&
      (current_path == target_path || current_path.start_with?("#{target_path}/"))
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
