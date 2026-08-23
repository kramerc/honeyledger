# frozen_string_literal: true

require "digest"
require "uri"

# Gives every linked git worktree its own development and test databases and
# its own development server port, so parallel sessions never share state.
#
# Everything here derives from one fact: the worktree's real path. There is no
# registry and no override to keep consistent; config/database.yml, bin/dev and
# bin/worktree-clean simply call these functions, and bin/worktree-clean can
# recognise a live worktree's databases because it computes them the same way.
#
# This is boot configuration, so it lives in config/ rather than lib/:
# database.yml is evaluated before the autoloader exists and the bin/ scripts
# run outside Rails entirely, so each caller requires it directly.
module WorktreeDatabase
  # Every worktree database carries this marker, so anything in PostgreSQL
  # without it is never this module's business. The primary checkout keeps the
  # plain, unmarked names.
  MARKER = "_wt_"

  # "honeyledger_development_wt_" already spends 27 of PostgreSQL's 63 bytes.
  MAX_LABEL_LENGTH = 20
  DIGEST_LENGTH = 8

  class << self
    # "" for the primary checkout; "_wt_<label>_<digest>" for a linked worktree.
    def suffix(application_root)
      linked_worktree?(application_root) ? worktree_suffix(application_root) : ""
    end

    # The suffix a worktree at `path` uses, whether or not it still exists.
    # The label is only for readability; the digest of the full real path is
    # what keeps two worktrees apart, including ones that share a directory
    # name or whose names differ only in punctuation.
    def worktree_suffix(path)
      path = real_path(path)
      label = File.basename(path).downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_|_\z/, "")[0, MAX_LABEL_LENGTH]
      label = "worktree" if label.empty?

      "#{MARKER}#{label}_#{Digest::SHA256.hexdigest(path)[0, DIGEST_LENGTH]}"
    end

    # A stable port per worktree, so servers from different worktrees do not
    # all race for 3000 and each worktree keeps the same URL between runs. The
    # primary checkout always prefers 3000.
    def preferred_port(application_root, base: 3000, span: 200)
      return base unless linked_worktree?(application_root)

      base + (Digest::SHA256.hexdigest(real_path(application_root))[0, 8].to_i(16) % span)
    end

    # A linked worktree's `.git` is a file pointing back at the main
    # repository; the primary checkout's `.git` is a directory.
    def linked_worktree?(application_root)
      File.file?(File.join(application_root, ".git"))
    end

    # True when DATABASE_URL names a database, either as its path or as a
    # `database=` query option; Active Record accepts both and gives either
    # precedence over database.yml, so the suffix would never reach the
    # connection and every worktree would share one database. A URL with
    # neither -- what CI supplies to pick a host and credentials -- is fine.
    def database_url_names_database?(url = ENV["DATABASE_URL"])
      return false if url.nil? || url.empty?

      uri = URI.parse(url)
      return true unless uri.path.to_s.delete_prefix("/").empty?

      URI.decode_www_form(uri.query.to_s).any? { |key, value| key == "database" && !value.empty? }
    rescue URI::InvalidURIError, ArgumentError
      false
    end

    private

    # Symlinks and relative segments must not make one worktree look like two,
    # or bin/worktree-clean would take a live worktree's database for an orphan.
    def real_path(path)
      File.realpath(path)
    rescue Errno::ENOENT
      File.expand_path(path)
    end
  end
end
