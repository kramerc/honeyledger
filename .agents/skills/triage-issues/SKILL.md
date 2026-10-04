---
name: triage-issues
description: Set Priority (P0–P2) and Size (XS–XL), with Estimate derived from Size, on the Honeyledger project board — for one issue just filed, a list of issue numbers, or every open issue still missing either field.
# The keys below are read by Claude Code and ignored by other agents.
argument-hint: "[issue-number ...]"
allowed-tools: Bash(bin/triage:*) Bash(gh issue view:*) Bash(gh issue list:*) Bash(gh api:*) Read Grep Glob
---

# Triage issues on the project board

Every open issue carries a **Priority** and a **Size** on the "Honeyledger" Projects v2 board, plus an **Estimate** derived from Size. They are board fields, not repo labels. This is the same procedure for every agent: the canonical copy lives at `.agents/skills/triage-issues/SKILL.md`, and the copies under `.claude/skills/` and `.github/skills/` are links to it.

`bin/triage` does the GitHub side. It looks up the project, field, and option IDs by name on every run, adds an issue to the board if the auto-add has not caught it yet, and will not overwrite a Priority or Size that is already set unless given `--force`. Estimate is the exception, described below.

```
bin/triage list                 # open issues missing Priority or Size, or with a stale Estimate (marked !)
bin/triage list --all           # every open issue with its current values (calibration)
bin/triage set N --priority P1 --size M
bin/triage sync-estimates       # repair Estimate on every sized issue; --dry-run to preview
```

**Estimate is never chosen.** Board columns can only total a number field, so Estimate is Size as a number: XS 1, S 2, M 3, L 5, XL 8 (`ProjectBoard::ESTIMATES`). `bin/triage set` writes it whenever it touches an issue with a Size, and corrects a stale one without `--force`. There is no option to set it by hand, and an Estimate edited on the board is put back the next time triage touches that issue.

## When this runs

- **Filing an issue.** An agent that opens an issue triages it right after `gh issue create`, in the same task, without being asked. The values follow from what the agent just wrote, so no separate request is needed.
- **On request.** With issue numbers, triage those. Without, run `bin/triage list` and triage everything it prints.
- **Not pull requests.** A PR's priority and size are those of the issue it closes, and a second copy on the PR would only drift. A PR with no issue is already sized by its diff by the time anyone looks at the board.

## Procedure

1. `bin/triage list --all` once, to see how existing issues are rated. Values the maintainer set are the calibration, so place new issues relative to them.
2. For each issue to triage, read the body and comments (`gh issue view N --comments`), plus any parent or sub-issues and linked PRs. For size, skim the code the issue names so the estimate reflects the real surface, not the title.
3. Choose both values using the rubric below. When torn between two values, pick the lower priority and the larger size.
4. `bin/triage set N --priority … --size …`. Estimate follows automatically. Fill only the fields that are empty. Never pass `--force` unless the user asked to re-triage that issue, because an existing value is the maintainer's call.
5. Leave **Status** and every field other than these three alone. Triage does not move an issue between columns.
6. Report a table to the user with the number, title, priority, size, and a one-line reason for each. Do not post comments on the issues; the board is the record.

## Priority

Ranks importance for a single-user personal finance app, where the ledger's correctness is the product.

| Value | Meaning | Typical cases |
|---|---|---|
| **P0** | Drop other work. Rare. | The ledger is wrong now: balances drift, transactions duplicate or vanish, imports from a feed in use fail or corrupt data. Cross-user data exposure or a security hole that is reachable in production. Production is down or deploys are blocked. |
| **P1** | Next up. | A defect with a workaround, or one that corrupts data only in an unusual path. A feature the maintainer has said is next, or one that unblocks other planned work. A `security` hardening with plausible real exposure. A `decision` that blocks a P1 issue. |
| **P2** | Whenever. The default. | Polish, layout, and nice-to-haves. `refactor` and `chore` work with no user-visible effect. Speculative ideas. A `decision` with nothing waiting on it. |

- A `bug` that silently changes ledger data outranks a visible one, which outranks a cosmetic one.
- Being in the **Ready** column means the maintainer has approved the issue as work, not that it is urgent. It is evidence for P1, not proof.
- An issue that was filed as a follow-up and deferred from a PR is usually P2 unless the deferral note says otherwise.
- Known Design Decisions in `AGENTS.md` that are recorded as low priority (for example issue 177) stay where they are.

## Size

Estimates the whole job: implementing, testing, and getting through the review sweep. It does not estimate the length of the diff.

| Value | Shape |
|---|---|
| **XS** | A few lines in one place: a validation, a copy fix, a doc tweak. One test at most. |
| **S** | One focused PR in one layer, such as a model method, a view fix, or a script option, with straightforward tests. |
| **M** | One PR across layers (model, controller, view, and system tests), or a migration, or a few design choices to make along the way. |
| **L** | More than one PR or a stacked pair. A new table or model plus its UI, or a change to import, reconcile, or merge logic where regressions are costly. Some design should be settled before starting. |
| **XL** | An epic. Split it into sub-issues before anyone starts, then size the children. Rating an issue XL is itself a signal to propose that split to the user. |

- Size a `decision` issue as the work to settle it plus the work to implement the option it currently leans toward.
- For a checklist issue, size the whole list. If the items are independent and the list would be L or bigger, suggest splitting it into sub-issues.
- Anchors from the board: a single model validation was XS; handling negative opening balances was M; the AutoMerge transfer-clone fix (issue 177) is L; migrating to a React frontend was XL.
