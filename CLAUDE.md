@AGENTS.md

## Claude Code specifics

Everything shared with other agents lives in `AGENTS.md` (imported above). Only Claude Code-specific tooling belongs here.

- **Worktrees.** Start isolated work with the `EnterWorktree` tool; it creates `.claude/worktrees/<name>` on a new branch. `bin/worktree-setup` runs automatically as a `SessionStart` hook, so secrets and the worktree database are ready without a manual step. When a PR's branch lives in a Claude worktree, merge from inside it (gh then skips local cleanup), then leave with `ExitWorktree` `action: "remove"`, `discard_changes: true`. The first attempt is always refused because the pre-squash commits aren't on `main`, and discarding them is safe once the PR is merged, the tree is clean, and the PR's files match `origin/main`. Finish with `git switch main && git pull --ff-only` in the primary checkout.
- **Review sweep.** `/sweep-pr [number]` runs the bounded review workflow from `AGENTS.md` ("Review sweep"); without a number it sweeps the current branch's PR. The file under `.claude/skills/` is a link to the canonical copy in `.agents/skills/`; edit that one, and start a fresh session to pick the change up (`/reload-skills` may not see it through the link).
- **Issue triage.** `/triage-issues [numbers]` sets Priority and Size on the project board (rubric in `.agents/skills/triage-issues/SKILL.md`, same link arrangement as `sweep-pr`). Without numbers it triages every open issue `bin/triage list` reports. After filing an issue, follow the skill without waiting to be asked.
- **Memory.** Claude's private memory holds conventions that are still provisional, personal, or volatile. Once a rule has proven stable and contains nothing about the user's own accounts or data, promote it to `AGENTS.md` so every agent gets it.
