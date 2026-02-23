module ApplicationHelper
  def preloaded_state_tag
    state = {
      user: current_user ? { id: current_user.id, email: current_user.email } : nil
    }
    content_tag(:script, id: "preloaded-state", type: "application/json") do
      state.to_json.html_safe
    end
  end
end
