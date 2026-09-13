# frozen_string_literal: true

require "json"

# Codex supplies hook input on stdin. Keep the shared worktree setup independent
# of its lifecycle protocol so Claude and manual invocations still use it as-is.
class CodexWorktreeSetupHook
  APP_ROOT = File.expand_path("..", __dir__)

  def self.run(input: $stdin, output: $stdout)
    payload = JSON.parse(input.read)
    if payload.fetch("permission_mode") == "plan"
      output.puts JSON.generate(systemMessage: "Worktree preparation skipped in Plan mode; run bin/worktree-setup before using Rails after leaving Plan mode.")
      return
    end

    setup_path = File.join(APP_ROOT, "bin/worktree-setup")
    unless system([ setup_path, setup_path ], chdir: APP_ROOT)
      output.puts JSON.generate(systemMessage: "Worktree preparation failed; run bin/worktree-setup in this checkout to diagnose it.")
    end
  rescue JSON::ParserError, KeyError, TypeError, NoMethodError
    output.puts JSON.generate(systemMessage: "Could not read Codex hook input; worktree preparation remains pending. Run bin/worktree-setup manually.")
  end
end
