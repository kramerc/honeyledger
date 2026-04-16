module ApplicationHelper
  def nav_link_to(name = nil, url = nil, options = {}, &block)
    if block_given?
      # nav_link_to(url, options) { content }
      options = url || {}
      url = name
      active = options.delete(:active)
    else
      active = options.delete(:active)
    end

    active_path = case active
    when :prefix then url
    when String then active
    end

    is_active = if active_path
      request.path == active_path || request.path.start_with?("#{active_path}/")
    else
      current_page?(url)
    end

    if is_active
      options[:class] = class_names(options[:class], "active")
    end

    if active_path
      data = (options[:data] ||= {})
      data[:nav_active_path] = active_path
    end

    if block_given?
      link_to url, options, &block
    else
      link_to name, url, options
    end
  end
end
