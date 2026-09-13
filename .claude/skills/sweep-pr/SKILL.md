---
name: sweep-pr
description: Run the bounded review sweep on a pull request — gates, one concurrent Copilot + Codex round, adjudicate every finding in the ledger comment, fix in one batch, verify the delta locally, stop by rule.
argument-hint: <pr-number>
disable-model-invocation: true
allowed-tools: Bash(bin/sweep-pr:*) Bash(gh pr:*) Bash(gh api:*) Bash(git:*) Bash(bin/rails test:*) Bash(bin/rubocop:*) Bash(bin/brakeman:*) Bash(bin/bundler-audit:*) Bash(bin/importmap:*) Read Edit Write Agent
---

# Review sweep for PR $ARGUMENTS

Bot reviews are nondeterministic: Copilot keeps finding new things and Codex may say "clean" on the same commit. This procedure bounds the loop. The rules live in `AGENTS.md` under "Review sweep"; `bin/sweep-pr` does the GitHub side deterministically. The only state is the PR's single ledger comment (starts with `<!-- sweep-ledger -->`), so rerunning this skill after a partial sweep resumes where it stopped.

Every `bin/sweep-pr` subcommand is safe to rerun. Only `request` and `ledger --write` post to GitHub, and neither ever duplicates a request or a comment.

## 1. Resume

```
bin/sweep-pr status $ARGUMENTS
bin/sweep-pr ledger $ARGUMENTS
```

Work in the worktree that has the PR branch checked out (`git worktree list`); enter one if none exists. The tree must be clean and at the PR head — `status` warns when it is not. If the base branch is not `main`, this is a stacked child: run the gates, then check the parent with `bin/sweep-pr status <parent>` and continue only once the parent reports its stop conditions met. When every PR in the stack is met it can be merged as one unit from GitHub's stack view; merging the parent alone is also fine, in which case retarget the child to `main` first (see "Stacked PRs" in `AGENTS.md`).

## 2. Gates

While the PR is a draft, run all six and fix until they pass. Commit and plain-push fixes; never amend.

```
bin/rails test
bin/rails test:system
bin/rubocop
bin/brakeman --no-pager
bin/bundler-audit
bin/importmap audit
```

When green and the PR is still a draft: `gh pr ready $ARGUMENTS`. That alone triggers Copilot and Codex, so it *is* round one — do not also request.

## 3. One concurrent request

```
bin/sweep-pr request $ARGUMENTS
```

It skips any bot that has already reviewed the head or has a request pending, and refuses to start a third round without `--force`. Then poll `bin/sweep-pr status $ARGUMENTS` about every two minutes for up to fifteen minutes until both bots are done for the head. If `status` reports the Codex request as dropped, run `request` once more. Never hand-post `@codex review` or the Copilot request.

## 4. Collect

```
bin/sweep-pr findings $ARGUMENTS > tmp/sweep-$ARGUMENTS.json
```

`tmp/` is gitignored. Each finding carries its `ledger_status` and any existing `replies`, so already-adjudicated and already-answered items are visible. Copilot's suppressed comments (low confidence, review-body only) are included — they have no thread and the ledger is their only record.

## 5. Adjudicate every open finding

Decide each one, in a ledger file (`tmp/sweep-$ARGUMENTS-ledger.json`, the shape `bin/sweep-pr ledger` prints):

- **rejected** with a `note`: a Known Design Decision from `AGENTS.md` (name it), or a trade-off deliberately declined — state cost versus cost.
- **duplicate** with `duplicate_of`: the same underlying issue already in the ledger under another id (earliest id wins).
- **deferred** with a `note`: valid but outside this PR; name the issue number in the note as "issue 123" (never a bare `#`) or say one should be filed.
- **accepted**: everything else. Suppressed findings are judged on merit; low confidence is not low severity.

Write the ledger *before* touching code so partial progress survives a crash:

```
bin/sweep-pr ledger $ARGUMENTS --write tmp/sweep-$ARGUMENTS-ledger.json
```

Findings you leave out are added as `open`; entries that do not justify their status are refused.

## 6. Fix accepted findings in one batch

One commit, or a few cohesive ones, with a regression test for each fix where one is possible. Plain push. Then update the ledger: `accepted` → `fixed` with `fixed_in` set to the bare commit SHA.

## 7. Tests

Targeted test files first, then all six gates from step 2.

## 8. Verify the fix delta locally

Give a fresh subagent only `git diff <reviewed-head>..HEAD` (the head the bots reviewed is in `status`) and ask for regressions and half-done fixes. Fold anything it finds back through step 5 and one small follow-up commit; if it needs more than that, treat it as a new round or hand it to the user. Record the result in the ledger as `verification: { base, head, result, note }` and write it. Do not request a bot for the delta.

## 9. Replies

For each **inline** finding whose `replies` has no maintainer entry, reply in its thread once, one-way, following the `AGENTS.md` GitHub Interaction rules: fixed → `Fixed in <sha>. <what changed, which test covers it>`; rejected, deferred, or duplicate → open with the attribution line ("Written by Claude Code, the agent that authored this PR."), give the cost-versus-cost, and offer to implement the alternative.

```
gh api -X POST repos/{owner}/{repo}/pulls/$ARGUMENTS/comments/<comment_id>/replies -F body=@tmp/reply.md
```

Suppressed findings have no thread; the ledger row is their adjudication. Never post a second summary comment.

## 10. Close out

Final `bin/sweep-pr ledger $ARGUMENTS --write …`, then `bin/sweep-pr status $ARGUMENTS`.

- **Stop** when it reports the stop conditions met: every finding terminal, CI green on the head, delta verified at the head.
- **Round two, once**: if not met, fewer than two rounds have run, and round one produced at least one accepted finding, go back to step 3. Never a third round.
- **Otherwise** list what remains for the user to adjudicate and stop. Anything a bot surfaces after the limit — a manual re-review, a late comment — is handled the same way: adjudicate in the ledger with the user, do not restart the loop.

A bot's "clean" is evidence, not certification. Copilot is the primary defect finder for Rails changes and Codex is independent coverage; they do not have to agree.

Report to the user: counts by status, the deferred list, the verification result, and anything that needs their call.
