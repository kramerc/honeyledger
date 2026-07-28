require "test_helper"
require "tmpdir"

class WorktreeDatabaseTest < ActiveSupport::TestCase
  # A linked worktree is identified by `.git` being a file rather than a
  # directory, so the fixtures below only need to create the right kind of entry.
  def with_checkout(linked:, relative_path: "worktree")
    Dir.mktmpdir do |base|
      root = File.join(base, relative_path)
      FileUtils.mkdir_p(root)

      if linked
        File.write(File.join(root, ".git"), "gitdir: #{base}/.git/worktrees/example\n")
      else
        FileUtils.mkdir_p(File.join(root, ".git"))
      end

      yield root
    end
  end

  test "the primary checkout keeps the plain, unsuffixed database names" do
    with_checkout(linked: false) do |root|
      assert_nil WorktreeDatabase.identity(root, override: nil)
      assert_equal "", WorktreeDatabase.suffix(root, override: nil)
    end
  end

  test "a linked worktree gets its own suffix" do
    with_checkout(linked: true, relative_path: "import-rules") do |root|
      suffix = WorktreeDatabase.suffix(root, override: nil)

      assert_match(/\A_import_rules_[0-9a-f]{6}\z/, suffix)
    end
  end

  test "a worktree under .claude/worktrees is named by its full subpath" do
    with_checkout(linked: true, relative_path: ".claude/worktrees/feature/nested") do |root|
      assert_equal "feature/nested", WorktreeDatabase.identity(root, override: nil)
    end
  end

  # Normalization and truncation both lose information. Without the digest,
  # these pairs would share databases and corrupt each other's schema.
  test "names that normalize or truncate alike still get distinct slugs" do
    [
      [ "feature-a", "feature_a" ],
      [ "feature/add-transaction-import-rules-v1", "feature/add-transaction-import-rules-v2" ]
    ].each do |first, second|
      assert_not_equal WorktreeDatabase.slug(first), WorktreeDatabase.slug(second),
        "#{first} and #{second} must not resolve to the same database"
    end
  end

  test "slugs are stable across calls" do
    assert_equal WorktreeDatabase.slug("feature/x"), WorktreeDatabase.slug("feature/x")
  end

  test "the override is sanitized into a legal identifier" do
    suffix = WorktreeDatabase.suffix("/anywhere", override: "Bad Name; DROP TABLE--")

    assert_match(/\A_[a-z0-9_]+\z/, suffix)
  end

  test "an empty override forces the plain database names" do
    with_checkout(linked: true) do |root|
      assert_equal "", WorktreeDatabase.suffix(root, override: "")
    end
  end

  test "database names stay within PostgreSQL's 63 byte identifier limit" do
    suffix = WorktreeDatabase.suffix("/anywhere", override: "x" * 200)

    assert_operator "honeyledger_development#{suffix}".bytesize, :<=, 63
  end

  test "a name with no alphanumeric characters still produces a usable slug" do
    assert_match(/\Aworktree_[0-9a-f]{6}\z/, WorktreeDatabase.slug("---"))
  end

  test "the primary checkout prefers port 3000" do
    with_checkout(linked: false) do |root|
      assert_equal 3000, WorktreeDatabase.preferred_port(root)
    end
  end

  test "a worktree prefers a stable port inside the scan range" do
    with_checkout(linked: true, relative_path: "import-rules") do |root|
      port = WorktreeDatabase.preferred_port(root)

      assert_equal port, WorktreeDatabase.preferred_port(root)
      assert_includes 3000...3200, port
    end
  end
end
