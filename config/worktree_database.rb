# frozen_string_literal: true

require "digest"

# Identifies the checkout a process is running from, so parallel git worktrees
# can be given their own databases and development server ports.
#
# config/database.yml, bin/dev, bin/worktree-setup and bin/worktree-clean must
# all agree on this derivation: if bin/worktree-clean computed a suffix even
# slightly differently from database.yml it would mistake a live worktree's
# database for an orphan. It lives in config/ rather than lib/ because
# database.yml loads it long before Zeitwerk is set up.
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
      name ? "_#{slug(name)}" : ""
    end

    # Normalized for PostgreSQL and made collision-proof. Both normalization
    # and truncation lose information, so "feature-a" and "feature_a", or any
    # two names sharing a long prefix, would otherwise resolve to the same
    # databases and corrupt each other. The digest is taken over the full name,
    # so distinct names always produce distinct slugs.
    def slug(name)
      normalized = name.downcase.gsub(/[^a-z0-9]+/, "_").delete_prefix("_").delete_suffix("_")
      normalized = "worktree" if normalized.empty?

      "#{normalized[0, MAX_SLUG_LENGTH]}_#{Digest::SHA256.hexdigest(name)[0, DIGEST_LENGTH]}"
    end

    # A stable port per checkout, so servers started from different worktrees
    # do not all race for 3000 and each worktree keeps the same URL between
    # runs. The primary checkout always prefers 3000.
    def preferred_port(application_root, base: 3000, span: 200)
      name = identity(application_root)
      return base unless name

      base + (Digest::SHA256.hexdigest(name)[0, 8].to_i(16) % span)
    end

    # A linked worktree's `.git` is a file pointing back at the main
    # repository; the primary checkout's is a directory.
    def linked_worktree?(application_root)
      File.file?(File.join(application_root, ".git"))
    end
  end
end
