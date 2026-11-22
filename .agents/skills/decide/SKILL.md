---
name: decide
description: File, deliberate, close, and propagate a `decision` issue — a design or process question settled before it becomes work. Runs on request (`/decide N`) and whenever an agent files a `decision` issue.
# The keys below are read by Claude Code and ignored by other agents.
argument-hint: "[issue-number]"
allowed-tools: Bash(gh issue:*) Bash(gh api:*) Bash(bin/triage:*) Read Grep Glob Edit Agent
---

# Settle a decision issue

A `decision` issue holds a design or process question that has to be answered before it can become a work item. This skill takes it through four phases: **file → deliberate → record & close → propagate**. Every agent follows the same procedure. The canonical copy lives at `.agents/skills/decide/SKILL.md`, and the copies under `.claude/skills/` and `.github/skills/` are links to it.

The issue is the only state. Rerunning this skill reads the issue body and comments to find out which phase it is in:

| What the issue shows | Phase |
|---|---|
| No **Decide** section, or sub-questions not yet laid out | 1. Filing (restructure the body) |
| Open, with sub-questions; maybe a `## Provisional direction` comment | 2. Deliberating |
| Maintainer sign-off in the session or a comment, but no `## Decision` comment | 3. Recording & closing |
| A `## Decision` comment exists but the banner is missing or the issue is still open | 3. Recording & closing, resumed: reuse that comment, never post a second one |
| Closed with a `## Decision` comment whose Follow-ups line still reads `pending` | 4. Propagating |

This skill takes one optional argument, the issue number, written as `N` below. Without it, run `gh issue list --label decision --state open`, read each issue, report its number, title, and phase in a table, and ask which one to work on.

## 1. Filing

This phase runs without being asked whenever an agent opens a `decision` issue. It also applies when an existing decision issue lacks this shape: propose the restructured body to the maintainer, and edit it only once they agree.

- **Title** starts with "Decide …" and states the question, not the answer: "Decide how cross-aggregator duplicates pick transacted_at", not "Use earliest transacted_at".
- **Body**, in this order:
  - **Context**: why the question matters now, and what prompted it.
  - **Decide**: one bullet per sub-question, each one answerable on its own.
  - **Options** (optional at filing): known options for each sub-question, described neutrally.
  - **Blocks**: the issues and work that wait on the outcome, including epic children deliberately held back (see "Splitting an epic" in the `triage-issues` skill). Record every blocked issue with `gh issue edit X --add-blocked-by N` as well; prose alone does not order the board.
  - **Done when**: the decision is recorded here and the issues it names are updated or filed.
- **Labels**: `decision` + `AI generated`, applied once on `gh issue create`.
- **Triage**: follow the `triage-issues` skill right after creating the issue. Its rubric covers decisions: P1 when the decision blocks a P1 issue, otherwise P2. Size is the work to settle the question plus the work to implement the option it currently leans toward.
- **Privacy**: the `AGENTS.md` Privacy rules apply. Describe an option by its shape, never with real ledger data.

## 2. Deliberating

1. Read the body, every comment (`gh api --paginate repos/{owner}/{repo}/issues/N/comments`), the parent issue, and every issue it blocks or is blocked by.
2. Read the code each sub-question touches, so the options reflect the real surface. Check "Known Design Decisions" in `AGENTS.md` (and, in Claude Code, memory) for earlier rulings that constrain the answer. If an option would overturn one, say so explicitly; never quietly re-propose a rejected idea.
3. For each sub-question, present 2–4 options to the maintainer in the session. Give each one as cost versus cost: what it changes in the codebase and on the board, and what it closes off later. Then give your lean and its reason. Use the tool's question prompt (`AskUserQuestion` in Claude Code) for genuine forks. Settle sub-questions one at a time when later ones depend on earlier answers.
4. **Only the maintainer decides.** An agent never records or closes a decision on its own judgment, however clear the answer looks.
5. When the discussion converges but the maintainer has not made the final call, post a `## Provisional direction` comment. Open it with the attribution line ("Written by <your agent name>, summarizing a discussion with the maintainer."), state plainly that the decision is still open, and leave the issue open. Issue 180 is the model.
6. When a sub-question blocks different work from the rest, or is stuck while the others are ready, split it off into its own decision issue (filed per phase 1) and link the two.

## 3. Recording & closing

Only after the maintainer has explicitly signed off on every sub-question.

1. **Post a `## Decision` comment** with these parts:
   - **Outcome**: one line per sub-question.
   - **Rationale**: the cost versus cost behind each choice.
   - **Rejected**: one line per option not taken and why, so it isn't proposed again.
   - **Consequences**: what changes and what deliberately stays.
   - **Follow-ups**: `pending` for now; phase 4 fills it in.

   Comments post under the maintainer's account. When the agent wrote the rationale, open with the attribution line and say the call was the maintainer's ("Written by <your agent name>; the maintainer made this decision in session.").
2. **Prepend a banner to the body** with `gh issue edit N --body-file`, changing nothing else:

   ```
   > **Decided YYYY-MM-DD:** <one-line outcome>. See <Decision comment URL>.
   ```

3. **Close the issue.**
   - `gh issue close N --reason completed` when an answer was chosen, including "keep the current behaviour".
   - `gh issue close N --reason "not planned"` when the question was dropped or superseded. Name the superseding issue in the Decision comment.
   - Keep the `decision` label, so closed decisions stay searchable as a log (`gh issue list --label decision --state closed`).
4. **Promote durable outcomes.** If the outcome is a rule a future agent would otherwise re-propose or break, add a short entry to "Known Design Decisions" in `AGENTS.md` that cites it as "issue N" (never a bare `#N`). Make the change in a worktree as a Markdown-only PR labelled `AI generated` + `documentation`; the gates are skipped for Markdown-only changes. A one-off outcome stays on the issue only.

## 4. Propagating

1. **Blocked issues.** For every issue under **Blocks** and every blocked-by link, update its body to match the outcome. Comment instead when an edit would erase discussion worth keeping. Remove the blocked-by link once nothing it guarded is still open (`gh issue edit X --remove-blocked-by N`).
2. **Held epic children.** File the children that were waiting on this decision, following "Splitting an epic into sub-issues" in the `triage-issues` skill: re-read any plan comment on the parent first (it may have been edited), list the parent's existing sub-issues (`gh api --paginate repos/{owner}/{repo}/issues/P/sub_issues`) so a rerun reuses children already filed instead of duplicating them, `gh issue create --parent P` for each one still missing, add blocked-by links, triage each child, then `bin/triage sync-estimates`.
3. **New work.** When the outcome needs implementation and no issue covers it (search for "Follows the decision in issue N" first, so a rerun does not file it twice), file the work item(s). Each body says "Follows the decision in issue N." Triage each one.
4. **Follow-ups line.** Edit the Decision comment so Follow-ups lists every issue edited or filed:

   ```
   gh api -X PATCH repos/{owner}/{repo}/issues/comments/<comment_id> -F body=@tmp/decision-N.md
   ```

5. **Claude Code only:** update or delete memory files that tracked the pending decision (for example, held epic splits waiting on it).
6. **Report to the user**: the outcome, the issues edited, filed, and triaged, and whether an `AGENTS.md` PR was opened.
