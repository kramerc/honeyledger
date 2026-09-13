# frozen_string_literal: true

require "test_helper"
require "json"
require "stringio"
require "open3"
require "tmpdir"
require "fileutils"
require Rails.root.join("lib/codex_worktree_setup_hook")

class CodexWorktreeSetupHookTest < ActiveSupport::TestCase
  test "startup and resume run the shared setup in the adapter checkout" do
    %w[startup resume].each do |source|
      arguments = []
      setup = ->(*command, **options) { arguments << [ command, options ]; true }
      output = StringIO.new

      CodexWorktreeSetupHook.stub(:system, setup) do
        CodexWorktreeSetupHook.run(input: hook_input(source: source), output: output)
      end

      setup_path = Rails.root.join("bin/worktree-setup").to_s
      assert_equal [ [ [ [ setup_path, setup_path ] ], { chdir: Rails.root.to_s } ] ], arguments
      assert_empty output.string
    end
  end

  test "Plan mode leaves preparation pending without running setup" do
    CodexWorktreeSetupHook.stub(:system, ->(*) { flunk "Plan mode must not prepare databases" }) do
      output = StringIO.new
      CodexWorktreeSetupHook.run(input: hook_input(permission_mode: "plan"), output: output)
      assert_includes JSON.parse(output.string).fetch("systemMessage"), "skipped in Plan mode"
    end
  end

  test "setup failure is reported" do
    CodexWorktreeSetupHook.stub(:system, false) do
      output = StringIO.new
      CodexWorktreeSetupHook.run(input: hook_input, output: output)
      assert_includes JSON.parse(output.string).fetch("systemMessage"), "preparation failed"
    end
  end

  test "invalid or incomplete input leaves setup pending" do
    [ "", "not json", "{}", "null", "[]" ].each do |payload|
      CodexWorktreeSetupHook.stub(:system, ->(*) { flunk "Invalid input must not prepare databases" }) do
        output = StringIO.new
        CodexWorktreeSetupHook.run(input: StringIO.new(payload), output: output)
        assert_includes JSON.parse(output.string).fetch("systemMessage"), "preparation remains pending"
      end
    end
  end

  test "configured hook runs from a root or subdirectory with spaces and preserves setup output" do
    configuration = JSON.parse(Rails.root.join(".codex/hooks.json").read)
    session_hook = configuration.fetch("hooks").fetch("SessionStart").sole
    matcher = Regexp.new(session_hook.fetch("matcher"))
    assert_match matcher, "startup"
    assert_match matcher, "resume"
    assert_no_match matcher, "compact"
    handler = session_hook.fetch("hooks").sole
    assert_equal 300, handler.fetch("timeout")
    assert_not handler["async"]

    Dir.mktmpdir("codex-hook") do |temporary_directory|
      root = File.join(temporary_directory, "checkout with spaces")
      FileUtils.mkdir_p([ File.join(root, "bin"), File.join(root, "lib"), File.join(root, "nested directory") ])
      FileUtils.cp(Rails.root.join("bin/codex-session-start"), File.join(root, "bin/codex-session-start"))
      FileUtils.cp(Rails.root.join("lib/codex_worktree_setup_hook.rb"), File.join(root, "lib/codex_worktree_setup_hook.rb"))
      setup_path = File.join(root, "bin/worktree-setup")
      File.write(setup_path, <<~RUBY)
        #!/usr/bin/env ruby
        require "json"
        puts JSON.generate(systemMessage: "Stub setup completed", directory: Dir.pwd)
      RUBY
      FileUtils.chmod(0o755, setup_path)
      _, git_error, git_status = Open3.capture3("git", "init", "--quiet", root)
      assert git_status.success?, git_error

      [ root, File.join(root, "nested directory") ].each do |directory|
        stdout, stderr, status = Open3.capture3("sh", "-c", handler.fetch("command"),
          chdir: directory, stdin_data: hook_input.read)
        assert status.success?, stderr
        message = JSON.parse(stdout)
        assert_equal "Stub setup completed", message.fetch("systemMessage")
        assert_equal File.realpath(root), message.fetch("directory")
      end
    end
  end

  private

  def hook_input(source: "startup", permission_mode: "default")
    StringIO.new(JSON.generate(source: source, permission_mode: permission_mode))
  end
end
