module ApplicationHelper
  def path_active?(current_path, target_path)
    current_path.present? && target_path.present? &&
      (current_path == target_path || current_path.start_with?("#{target_path}/"))
  end

  def nav_link_to(name = nil, url = nil, options = {}, &block)
    if block_given?
      # nav_link_to(url, options) { content }
      options = url || {}
      url = name
      active = options.delete(:active)
    else
      active = options.delete(:active)
    end

    is_active = case active
    when :prefix
      path_active?(request.path, url)
    when String
      path_active?(request.path, active)
    else
      current_page?(url)
    end

    if is_active
      options[:class] = class_names(options[:class], "active")
    end

    if block_given?
      link_to url, options, &block
    else
      link_to name, url, options
    end
  end
end
