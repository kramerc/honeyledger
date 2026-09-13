# Codex worktrees

Use the same worktree workflow on Linux, macOS, or Windows through WSL. Run
Codex and Rails commands in the environment where Ruby, Git, the project gems,
and PostgreSQL are available. On Windows, use WSL for those commands. Shared
development conventions live in [AGENTS.md](../AGENTS.md).

## New work

From the primary checkout, choose an unused name and create a worktree:

```sh
git worktree add .codex/worktrees/<name> -b codex/<name>
cd .codex/worktrees/<name>
bin/worktree-setup
codex
```

Codex worktrees use `.codex/worktrees/`; Claude Code keeps
`.claude/worktrees/`. Each session needs its own directory and branch. If an
agent creates its worktree after starting a session, it must run setup there
explicitly and use that checkout for all subsequent work. Do not create another
worktree inside an existing worktree.

## Automatic preparation

The repository's `.codex/hooks.json` runs `bin/codex-session-start` on startup
and resume. The adapter calls the existing `bin/worktree-setup` in that checkout:
credentials are symlinked from the primary checkout and the worktree's own
development/test databases are prepared. The primary checkout is a no-op.
Starting from a subdirectory works too. Plan-mode sessions skip preparation and
report that it remains pending; run setup after leaving Plan mode before using
Rails.

Codex CLI 0.154.0 discovers a linked worktree's repository hook definitions in
the primary checkout's `.codex/` directory. Make this configuration available in
the primary checkout (normally by merging it) before expecting automatic setup
in linked worktrees. The hook command still resolves and runs the adapter from
the active worktree. A worktree based on an older commit without the adapter
needs manual setup until it includes this change.

In Codex CLI, open `/hooks` to inspect and trust the repository hook. Project
trust alone does not approve hooks: new or changed hook definitions need their
own review. Restart or resume the session after trusting the hook, or run
`bin/worktree-setup` manually. See the [Codex hook documentation](https://learn.chatgpt.com/docs/hooks).

If hooks are unavailable, disabled, or untrusted, run `bin/worktree-setup`
manually. Its warning about a database-specific `DATABASE_URL` means isolation
is not ready: unset the override or remove its database path before retrying.
A database-preparation warning also means setup is incomplete; run
`bin/rails db:prepare` in the worktree to diagnose it. A zero exit status alone
is not proof of readiness because the shared setup script reports failures as
warnings so sessions can still start.

No global Codex credentials or settings are copied into worktrees. The
experimental Codex-managed worktree feature is not needed or enabled by this
configuration.

## Continue work and use the app

Start Codex in the same worktree directory when continuing work, using
`codex resume` to select the existing session. For occasional app use, open that
prepared worktree as the project and use its local checkout. Run Rails commands
in the same Linux, macOS, or WSL environment used to prepare it. This
configuration does not provision native Windows or app-managed worktrees.

## Devcontainer follow-up

The repository also has a `.devcontainer/` configuration, but Codex worktree
support inside it has not been validated. Treat that as a separate follow-up.
Check Git metadata and credential symlinks across host/container paths, setup
hooks, database isolation, and ports for parallel sessions. The current container
uses a fixed Compose project name, forwards app port 3000, and sets a fixed
Capybara server port; review those assumptions before relying on concurrent
worktrees in containers.

## Cleanup

After preserving the work, remove its worktree with `git worktree remove <path>`.
From the primary checkout, `bin/worktree-clean` recognizes worktrees in both
locations. Use `bin/worktree-clean --drop` to remove orphaned test databases;
development databases are only reported for manual removal. Do not automatically
remove worktrees when a Codex session ends.
