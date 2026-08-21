# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require Rails.root.join("config", "worktree_database").to_s

class WorktreeDatabaseTest < ActiveSupport::TestCase
  # A linked worktree's `.git` is a file; the primary checkout's is a directory.
  def primary_checkout = make_checkout("primary") { |root| Dir.mkdir(File.join(root, ".git")) }
  def linked_worktree(name = "feature") = make_checkout(name) { |root| File.write(File.join(root, ".git"), "gitdir: elsewhere") }

  teardown { @tmpdirs&.each { |dir| FileUtils.rm_rf(dir) } }

  def tmpdir = (@tmpdirs ||= []).push(Dir.mktmpdir).last

  def make_checkout(name)
    root = File.join(tmpdir, name)
    Dir.mkdir(root)
    yield root
    root
  end

  test "primary checkout keeps unsuffixed names and port 3000" do
    root = primary_checkout
    assert_equal "", WorktreeDatabase.suffix(root)
    assert_equal 3000, WorktreeDatabase.preferred_port(root)
  end

  test "linked worktree suffix is marked, labelled by directory name, and digest-qualified" do
    assert_match(/\A_wt_feature_\h{8}\z/, WorktreeDatabase.suffix(linked_worktree("feature")))
  end

  test "label is sanitized and truncated but the digest keeps distinct paths distinct" do
    a = WorktreeDatabase.suffix(linked_worktree("Feature-A"))
    b = WorktreeDatabase.suffix(linked_worktree("feature_a"))
    long = WorktreeDatabase.suffix(linked_worktree("a-very-long-worktree-name-that-keeps-going"))

    assert_match(/\A_wt_feature_a_\h{8}\z/, a)
    assert_match(/\A_wt_feature_a_\h{8}\z/, b)
    assert_not_equal a, b
    assert_operator "honeyledger_development#{long}".length, :<=, 63
  end

  test "worktrees sharing a directory name under different parents get different suffixes" do
    assert_not_equal WorktreeDatabase.suffix(linked_worktree("same")), WorktreeDatabase.suffix(linked_worktree("same"))
  end

  test "a symlink to a worktree resolves to the same suffix as the worktree" do
    root = linked_worktree
    link = File.join(tmpdir, "alias")
    File.symlink(root, link)

    assert_equal WorktreeDatabase.suffix(root), WorktreeDatabase.suffix(link)
  end

  test "worktree_suffix is stable and does not require the path to exist" do
    assert_match(/\A_wt_gone_\h{8}\z/, WorktreeDatabase.worktree_suffix("/nonexistent/gone"))
    assert_equal WorktreeDatabase.worktree_suffix("/nonexistent/gone"), WorktreeDatabase.worktree_suffix("/nonexistent/gone")
  end

  test "linked worktree port is stable and inside the span above the base" do
    root = linked_worktree
    port = WorktreeDatabase.preferred_port(root, base: 3000, span: 200)

    assert_equal port, WorktreeDatabase.preferred_port(root, base: 3000, span: 200)
    assert_includes 3000...3200, port
  end

  test "database_url_names_database? only when the URL has a database path" do
    assert_not WorktreeDatabase.database_url_names_database?(nil)
    assert_not WorktreeDatabase.database_url_names_database?("")
    assert_not WorktreeDatabase.database_url_names_database?("postgres://postgres:postgres@localhost")
    assert_not WorktreeDatabase.database_url_names_database?("postgres://localhost/")
    assert WorktreeDatabase.database_url_names_database?("postgres://localhost/honeyledger_test")
    assert_not WorktreeDatabase.database_url_names_database?("not a url")
  end
end
