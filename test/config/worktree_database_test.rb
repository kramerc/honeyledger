require "test_helper"
require "tmpdir"

# Required explicitly rather than autoloaded: config/ is not on the autoload
# path, and config/database.yml and the bin/ scripts load this by hand too.
require Rails.root.join("config", "worktree_database").to_s

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

  # Only a path-derived suffix proves exclusive ownership. An override may be
  # exported for the primary checkout or another worktree, so databases created
  # under one are never registered as reclaimable.
  test "a worktree owns its databases only when the suffix comes from its path" do
    with_checkout(linked: true) do |root|
      assert WorktreeDatabase.path_derived?(root, override: nil)
      assert_not WorktreeDatabase.path_derived?(root, override: "alice")
      assert_not WorktreeDatabase.path_derived?(root, override: "")
    end
  end

  test "the primary checkout never owns worktree databases" do
    with_checkout(linked: false) do |root|
      assert_not WorktreeDatabase.path_derived?(root, override: nil)
    end
  end

  # override: nil throughout, so the port assertions describe the checkout
  # rather than whatever HONEYLEDGER_DB_SUFFIX happens to be set to.
  test "the primary checkout prefers port 3000" do
    with_checkout(linked: false) do |root|
      assert_equal 3000, WorktreeDatabase.preferred_port(root, override: nil)
    end
  end

  test "a worktree prefers a stable port inside the scan range" do
    with_checkout(linked: true, relative_path: "import-rules") do |root|
      port = WorktreeDatabase.preferred_port(root, override: nil)

      assert_equal port, WorktreeDatabase.preferred_port(root, override: nil)
      assert_includes 3000...3200, port
    end
  end

  test "preferred_port honours an override the same way suffix does" do
    with_checkout(linked: false) do |root|
      assert_not_equal 3000, WorktreeDatabase.preferred_port(root, override: "alice")
    end
  end
end

class WorktreeDatabaseRegistryTest < ActiveSupport::TestCase
  def with_primary_checkout
    Dir.mktmpdir { |root| yield root }
  end

  test "reading a registry that does not exist yields no entries" do
    with_primary_checkout { |root| assert_empty WorktreeDatabase::Registry.read(root) }
  end

  test "reading a corrupt registry yields no entries rather than raising" do
    with_primary_checkout do |root|
      FileUtils.mkdir_p(File.join(root, "tmp"))
      File.write(WorktreeDatabase::Registry.path(root), "{not json")

      assert_empty WorktreeDatabase::Registry.read(root)
    end
  end

  test "updates round-trip through the registry file" do
    with_primary_checkout do |root|
      WorktreeDatabase::Registry.update(root) { |registry| registry["/a"] = "_a_000001" }
      WorktreeDatabase::Registry.update(root) { |registry| registry["/b"] = "_b_000002" }

      assert_equal({ "/a" => "_a_000001", "/b" => "_b_000002" }, WorktreeDatabase::Registry.read(root))
    end
  end

  test "a removed worktree's suffix is reclaimable" do
    registry = { "/gone" => "_gone_000001", "/live" => "_live_000002" }

    assert_equal({ "/gone" => "_gone_000001" }, WorktreeDatabase::Registry.reclaimable(registry, [ "/live" ]))
  end

  # An empty suffix names the primary checkout's own databases, which is what a
  # worktree bootstrapped under HONEYLEDGER_DB_SUFFIX="" records. Reclaiming it
  # would drop honeyledger_development itself.
  test "an empty suffix is never reclaimable" do
    registry = { "/gone" => "" }

    assert_empty WorktreeDatabase::Registry.reclaimable(registry, [])
  end

  # Ownership is per-suffix, not per-path: two worktrees sharing an override
  # share databases, so removing one must not drop them from under the other.
  test "a suffix still used by a live worktree is not reclaimable" do
    registry = { "/gone" => "_shared_000001", "/live" => "_shared_000001" }

    assert_empty WorktreeDatabase::Registry.reclaimable(registry, [ "/live" ])
  end

  # Worktrees are bootstrapped concurrently by design. Without the lock, one
  # process's entry overwrites another's and the loser's databases can never be
  # reclaimed, so this exercises real concurrent processes rather than threads.
  test "concurrent updates from separate processes do not lose entries" do
    with_primary_checkout do |root|
      worktree_count = 8

      pids = worktree_count.times.map do |index|
        fork do
          WorktreeDatabase::Registry.update(root) { |registry| registry["/worktree-#{index}"] = "_w#{index}_000000" }
          exit!(0)
        end
      end

      pids.each { |pid| Process.wait(pid) }

      registry = WorktreeDatabase::Registry.read(root)
      assert_equal worktree_count, registry.size
      worktree_count.times { |index| assert_includes registry, "/worktree-#{index}" }
    end
  end
end
