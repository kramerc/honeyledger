# Copilot Instructions for Honeyledger

Both Copilot's coding agent and Copilot code review on GitHub.com read `AGENTS.md` at the repository root, which is the canonical instruction file for every coding agent. Everything about architecture, commands, testing, conventions, privacy, and the Git/GitHub workflow lives there. This file holds only what is specific to Copilot.

## Copilot specifics

- **Coding agent environment.** Copilot runs in its own ephemeral checkout on GitHub Actions, so the worktree setup in `AGENTS.md` does not apply. The test database comes from CI's `DATABASE_URL`; run `bin/rails db:prepare` before tests if it has not been created.
- **PRs you open** follow the Git & PR Workflow in `AGENTS.md`: `AI generated` plus a category label, a closing keyword once in the PR body, no `(#NN)` in commit subjects. Never merge, force-push, or deploy (`kamal deploy`) yourself.
- **Reviews you post** follow the GitHub Interaction rules in `AGENTS.md`; the Known Design Decisions listed there are not findings.
