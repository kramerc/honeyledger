# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "uri"

# Identifies the checkout a process is running from, so parallel git worktrees
# can be given their own databases and development server ports.
#
# config/database.yml, bin/dev, bin/worktree-setup and bin/worktree-clean must
# all agree on this derivation: if bin/worktree-clean computed a suffix even
# slightly differently from database.yml it would mistake a live worktree's
# database for an orphan.
#
# This is boot configuration rather than application code, which is why it lives
# in config/ and not lib/. Every caller requires it directly: database.yml is
# evaluated before the autoloader exists, and the bin/ scripts run outside Rails
# entirely. Under lib/ it would need excluding from autoload_lib (Zeitwerk must
# not also own a hand-loaded file) and from SimpleCov (it is loaded during boot,
# before Coverage starts, so it can never be measured); config/ needs neither.
module WorktreeDatabase
  WORKTREE_DIRECTORY = "/.claude/worktrees/"

  # "honeyledger_development_" already spends 24 of PostgreSQL's 63 bytes.
  MAX_SLUG_LENGTH = 24
  DIGEST_LENGTH = 6

  class << self
    # The raw name identifying this checkout, or nil for the primary checkout,
    # which keeps the plain, unsuffixed database names. Setting the override to
    # an empty string forces those plain names.
    def identity(application_root, override: ENV["HONEYLEDGER_DB_SUFFIX"])
      return nil if override&.empty?
      return override if override
      return nil unless linked_worktree?(application_root)

      if application_root.include?(WORKTREE_DIRECTORY)
        application_root.split(WORKTREE_DIRECTORY, 2).last
      else
        File.basename(application_root)
      end
    end

    # The suffix appended to the development and test database names.
    def suffix(application_root, **options)
      name = identity(application_root, **options)
      name ? "_#{slug(name, uniqueness_key(application_root, **options))}" : ""
    end

    # What actually distinguishes one checkout from another. The identity is
    # only a label and repeats freely -- worktrees at /tmp/session-a/feature and
    # /tmp/session-b/feature are both called "feature" -- so uniqueness comes
    # from the full path instead. An override is deliberately shareable and
    # stands for itself.
    def uniqueness_key(application_root, override: ENV["HONEYLEDGER_DB_SUFFIX"])
      override || application_root
    end

    # A readable label plus a digest that makes it collision-proof. Normalization
    # and truncation both lose information, so "feature-a" and "feature_a", or
    # any two names sharing a long prefix, would otherwise resolve to the same
    # databases and corrupt each other.
    #
    # The digest is taken over `digest_source`, which defaults to the name but is
    # the full checkout path when called from suffix/preferred_port, so two
    # worktrees that merely share a directory name stay separate.
    def slug(name, digest_source = name)
      normalized = name.downcase.gsub(/[^a-z0-9]+/, "_").delete_prefix("_").delete_suffix("_")
      normalized = "worktree" if normalized.empty?

      "#{normalized[0, MAX_SLUG_LENGTH]}_#{Digest::SHA256.hexdigest(digest_source)[0, DIGEST_LENGTH]}"
    end

    # A stable port per checkout, so servers started from different worktrees
    # do not all race for 3000 and each worktree keeps the same URL between
    # runs. The primary checkout always prefers 3000.
    def preferred_port(application_root, base: 3000, span: 200, **options)
      return base unless identity(application_root, **options)

      key = uniqueness_key(application_root, **options)
      base + (Digest::SHA256.hexdigest(key)[0, 8].to_i(16) % span)
    end

    # A linked worktree's `.git` is a file pointing back at the main
    # repository; the primary checkout's is a directory.
    def linked_worktree?(application_root)
      File.file?(File.join(application_root, ".git"))
    end

    # True when the suffix derives from the worktree path alone, which is the
    # only case where a worktree exclusively owns its databases.
    #
    # An override is user-supplied and says nothing about ownership: the same
    # value may be exported for the primary checkout or for another worktree,
    # and the primary checkout is never registered at all. Databases created
    # under an override are therefore never recorded as reclaimable.
    def path_derived?(application_root, override: ENV["HONEYLEDGER_DB_SUFFIX"])
      override.nil? && linked_worktree?(application_root)
    end

    # True when DATABASE_URL names a database. Active Record gives the URL's
    # database precedence over the `database:` key in database.yml, so the
    # per-worktree suffix never reaches the connection and every worktree shares
    # one database. Claiming isolation in that case would be worse than not
    # having the feature, so callers must check this before promising anything.
    #
    # A URL with no path -- which is what CI supplies to select a host and
    # credentials only -- leaves the YAML database name in force and is fine.
    def database_url_names_database?(url = ENV["DATABASE_URL"])
      return false if url.nil? || url.empty?

      !URI.parse(url).path.to_s.delete_prefix("/").empty?
    rescue URI::InvalidURIError
      false
    end

    # Whether this checkout genuinely has databases of its own.
    def isolated?(application_root, **options)
      path_derived?(application_root, **options) && !database_url_names_database?
    end
  end

  # Records which databases were created for which worktree, so bin/worktree-clean
  # only ever drops databases it can prove bin/worktree-setup created. It lives in
  # the primary checkout and is keyed by worktree path.
  module Registry
    class << self
      def path(primary_checkout)
        File.join(primary_checkout, "tmp", "worktree_databases.json")
      end

      def read(primary_checkout)
        JSON.parse(File.read(path(primary_checkout)))
      rescue Errno::ENOENT, JSON::ParserError
        {}
      end

      # Runs the block holding the registry's exclusive lock. Registration and
      # cleanup both take it, so a worktree cannot be bootstrapped while
      # bin/worktree-clean is deciding what is safe to drop.
      def with_lock(primary_checkout)
        registry_path = path(primary_checkout)
        FileUtils.mkdir_p(File.dirname(registry_path))

        File.open("#{registry_path}.lock", File::RDWR | File::CREAT, 0o644) do |lock|
          lock.flock(File::LOCK_EX)
          yield
        end
      end

      # Read-modify-write under that lock, replacing the file atomically.
      # Worktrees are bootstrapped concurrently by design, so an unguarded
      # read-then-write would let one worktree's entry overwrite another's, and
      # the loser's databases could never be reclaimed.
      def update(primary_checkout)
        with_lock(primary_checkout) do
          registry = read(primary_checkout)
          yield registry

          write(primary_checkout, registry)
          registry
        end
      end

      def write(primary_checkout, registry)
        registry_path = path(primary_checkout)
        temporary_path = "#{registry_path}.#{Process.pid}.tmp"

        File.write(temporary_path, JSON.pretty_generate(registry))
        File.rename(temporary_path, registry_path)
      end

      # The registry entries whose databases are safe to drop: worktrees that
      # are gone, minus anything another checkout still relies on.
      #
      # An empty suffix names the primary checkout's own databases, which is
      # what a worktree bootstrapped under HONEYLEDGER_DB_SUFFIX="" records, and
      # dropping those would destroy the main development database. A suffix
      # shared with a live entry belongs to a worktree that is still using it.
      # Ownership is per-suffix, not per-path, so neither is reclaimable.
      def reclaimable(registry, live_worktree_paths)
        gone = registry.reject { |worktree_path, _suffix| live_worktree_paths.include?(worktree_path) }
        live_suffixes = (registry.keys - gone.keys).map { |worktree_path| registry[worktree_path] }

        gone.reject { |_worktree_path, suffix| suffix.to_s.empty? || live_suffixes.include?(suffix) }
      end
    end
  end
end
