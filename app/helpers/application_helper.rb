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

    is_active = case active
    when :prefix
      request.path == url || request.path.start_with?("#{url}/")
    when String
      request.path == active || request.path.start_with?("#{active}/")
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
