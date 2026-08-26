@AGENTS.md

## Claude Code specifics

Everything shared with other agents lives in `AGENTS.md` (imported above). Only Claude Code-specific tooling belongs here.

- **Worktrees.** Start isolated work with the `EnterWorktree` tool; it creates `.claude/worktrees/<name>` on a new branch. `bin/worktree-setup` runs automatically as a `SessionStart` hook, so secrets and the worktree database are ready without a manual step.
- **Projects v2 IDs** for the Priority and Size fields described in `AGENTS.md` — re-query if they stop resolving:
  - Project: `PVT_kwHOAAG9iM4BPFrE`
  - Priority field `PVTSSF_lAHOAAG9iM4BPFrEzg9mcIE` — P0 `79628723`, P1 `0a877460`, P2 `da944a9c`
  - Size field `PVTSSF_lAHOAAG9iM4BPFrEzg9mcII` — XS `6c6483d2`, S `f784b110`, M `7515a9f1`, L `817d0097`, XL `db339eb2`
- **Memory.** Claude's private memory holds conventions that are still provisional, personal, or volatile. Once a rule has proven stable and contains nothing about the user's own accounts or data, promote it to `AGENTS.md` so every agent gets it.
