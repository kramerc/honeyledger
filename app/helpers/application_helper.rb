module ApplicationHelper
  def nav_link_to(name, url, options = {})
    active = options.delete(:active)
    is_active = case active
    when :prefix
      request.path == url || request.path.start_with?("#{url}/")
    else
      current_page?(url)
    end

    if is_active
      options[:class] = class_names(options[:class], "active")
    end

    link_to name, url, options
  end
end
