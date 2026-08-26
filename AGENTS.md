# AGENTS.md

Guidance for any coding agent working in this repository. Codex, Copilot (coding agent and code review), and Claude Code (via the `@AGENTS.md` import in `CLAUDE.md`) all read this file directly. It is the canonical source: anything true for every agent lives here. A rule that applies to one tool only belongs in that tool's own file (`CLAUDE.md`, `.github/copilot-instructions.md`), which should otherwise defer to this one.

## Overview

Honeyledger is a personal finance management Rails 8.1 app that syncs financial transactions from banks via aggregator APIs (SimpleFIN and Lunch Flow) and supports double-entry bookkeeping.

**Stack:** Ruby on Rails 8.1, PostgreSQL, Devise, Hotwire (Turbo + Stimulus), Propshaft + importmap, Minitest, Kamal deployment.

## Commands

```bash
bin/dev                                          # Start dev server
bin/rails test                                   # Run all tests
bin/rails test test/models/account_test.rb       # Run a single test file
bin/rails test:system                            # Run system tests (Capybara/Selenium)
bin/rubocop                                      # Lint (Rails Omakase style)
bin/rubocop -a                                   # Lint with auto-fix
bin/brakeman --no-pager                          # Security scan (Ruby)
bin/bundler-audit                                # Security scan (gems)
bin/importmap audit                              # Security scan (JS)
bin/setup                                        # Bootstrap project
bin/rails db:create db:migrate                   # Set up database
bin/worktree-clean --drop                        # Drop test databases left by deleted worktrees
kamal deploy                                     # Deploy to production
```

## Parallel Development

The repo supports several agent sessions working at once, each in its own git
worktree. **Start isolated work in a worktree**
(`git worktree add .claude/worktrees/<name> -b <branch>`) and reserve the primary
checkout at `/home/kramer/Dev/Honeyledger/honeyledger` for review, merging, and
anything that must see `main`.

Everything derives from the worktree's path, via `config/worktree_database.rb`:

- **Databases.** A linked worktree's development and test databases are named
  `honeyledger_<env>_wt_<label>_<digest>`; the primary checkout keeps the plain
  names and production is untouched. Two sessions can run `bin/rails test` at
  once, and a migration on one branch cannot break another.
- **Secrets and local settings.** Run `bin/worktree-setup` after creating a
  worktree: it symlinks the gitignored `config/master.key` and
  `.claude/settings.local.json` from the primary checkout and runs
  `db:prepare`. It is idempotent and a no-op in the primary checkout.
- **Ports.** `bin/dev` picks a stable port per worktree (the primary checkout
  prefers 3000) and falls forward if it is taken. Set `PORT` to pin one.

**Still shared** — coordinate before touching: the `main` branch and remote, the
primary checkout's `honeyledger_development`, and real aggregator credentials.

**Cleanup.** `git worktree remove` leaves databases behind. From the primary
checkout, `bin/worktree-clean` lists them and `--drop` removes the orphaned
**test** databases (rebuilt from `db/schema.rb` on demand). Orphaned development
databases are only ever reported with the `dropdb` command to run by hand.

**Caveat.** `DATABASE_URL` naming a database outranks `database.yml` and defeats
the isolation; `bin/worktree-setup` warns instead of claiming it. A URL with no
database path (what CI uses) is fine.

## Architecture

### Domain Model (Double-Entry Bookkeeping)

Every `Transaction` has `src_account` and `dest_account` (both FK to `accounts`). Amounts are stored as integers in `amount_minor` (smallest currency unit). Account `balance_minor` is kept in sync via `after_save`/`after_destroy` callbacks using `update_counters` for atomic updates.

**`Account`** — `kind` enum: `asset`, `liability`, `equity`, `expense`, `revenue`. Accounts can be `real` (with currency and balance) or `virtual` (bookkeeping counterparts for opening balances).

**`Account`** links to aggregator accounts through `account_sources` (`has_many :account_sources`); each join row carries a polymorphic `sourceable` (`Simplefin::Account` or `Lunchflow::Account`). A ledger account may have several sources, but each aggregator account belongs to at most one ledger account (unique index on `sourceable_type, sourceable_id`). The `unlinked` scope finds accounts with no `account_sources`.

**`Transaction`** — Supports FX (`fx_amount_minor` + `fx_currency_id`), split transactions (`parent_transaction_id`, `split` flag), opening balances (`opening_balance` flag), and source tracking through `transaction_sources` (`has_many :transaction_sources`), whose polymorphic `sourceable` is a `Simplefin::Transaction`, `Lunchflow::Transaction`, or `Csv::Transaction`. `transaction_sources` is a polymorphic join table so that one ledger transaction can hold rows from several feeds at once (SimpleFIN, Lunch Flow, CSV) without a per-feed foreign key, provenance survives relinking an account to a different aggregator, and the attachment can carry its own metadata (`direction_overridden`). It is still one-to-many at the row level: each source record attaches to at most one ledger transaction (unique index on `sourceable_type, sourceable_id`), so a source is never shared or re-parented. Canonical fields (description, amount, date) are **first-writer-wins** — later sources attach without overwriting. `Transaction::Reconcile` attaches an incoming source to an existing ledger transaction when amount, currency, a small date window, and a normalized description match, and abstains when the match is ambiguous.

### `Minorable` Concern (`app/models/concerns/minorable.rb`)

Two class macros for handling minor-unit currency math:
- `minorable :amount, with: :currency` — computes read-only `amount_minor` from a decimal column scaled by `currency.decimal_places`
- `unminorable :amount_minor, with: :currency` — adds a read/write `amount` virtual attribute that converts to/from `amount_minor` via `before_save`, with deferred currency resolution

Used by `Transaction`, `Simplefin::Account`, `Simplefin::Transaction`, `Lunchflow::Account`, and `Lunchflow::Transaction`.

### Aggregator Integration Pattern

Both SimpleFIN and Lunch Flow follow the same namespaced pattern: `Connection` → `Account` → `Transaction`, with a refresh job to sync from the API and a namespaced `ImportTransactionsJob` to create ledger transactions. Aggregator accounts link to ledger accounts through `account_sources`. Linking triggers `ImportTransactionsJob`, and refresh jobs automatically enqueue it for linked accounts after each successful account refresh. A unified `/integrations` page managed by `IntegrationsController` shows both connections and all aggregator accounts.

### SimpleFIN Integration

1. **`lib/simplefin_client.rb`** (`SimplefinClient`) — HTTParty wrapper. `claim(token)` exchanges a setup token for a persistent access URL; `accounts(start_date:)` fetches raw account and transaction data.

2. **`app/models/simplefin/`** — Three models:
   - `Simplefin::Connection` — Stores access URL (basic-auth credentials in URL) per user; `refresh` enqueues `Simplefin::RefreshJob`
   - `Simplefin::Account` — Raw account data; linked to a ledger `Account` through `account_sources`; `suggested_opening_balance` computes a starting balance from historical transactions
   - `Simplefin::Transaction` — Raw transaction records; `has_many :transaction_sources, as: :sourceable` and `has_many :ledger_transactions, through: :transaction_sources`

3. **`Simplefin::RefreshJob`** — Upserts `Simplefin::Account` and `Simplefin::Transaction` records from the API

### Lunch Flow Integration

1. **`lib/lunchflow_client.rb`** (`LunchflowClient`) — HTTParty wrapper with `x-api-key` header auth. `accounts` lists accounts; `balance(account_id)` and `transactions(account_id)` fetch per-account data. Raises `UnauthorizedError` on 401/403, `Error` on other failures.

2. **`app/models/lunchflow/`** — Three models mirroring SimpleFIN:
   - `Lunchflow::Connection` — Stores API key per user; `refresh` enqueues `Lunchflow::RefreshJob`; `error` column stores API error messages
   - `Lunchflow::Account` — Raw account data with `institution_name`, `provider`, `status` (ACTIVE/ERROR/DISCONNECTED); linked to a ledger `Account` through `account_sources`
   - `Lunchflow::Transaction` — Raw transaction records with `merchant` field; linked to app `Transaction` through `transaction_sources`, like `Simplefin::Transaction`

3. **`Lunchflow::RefreshJob`** — Fetches accounts, balances, and transactions per-account. Rescues `LunchflowClient::Error` and stores message on connection.

### ImportTransactionsJob

Each aggregator namespace has its own `ImportTransactionsJob` (`Simplefin::ImportTransactionsJob`, `Lunchflow::ImportTransactionsJob`) that converts aggregator transactions to app `Transaction` records with double-entry bookkeeping. Negative amount = expense (auto-creates expense account), positive = revenue. Lunch Flow imports prefer `merchant` over `description`. Each job requires a specific account ID. RefreshJobs automatically enqueue import jobs for linked accounts after a successful per-account refresh.

Direction is not derived from the sign alone. `Transaction::InferLedgerSide` (`app/services/transaction/infer_ledger_side.rb`) applies one override on top of it: a feed that signs *both* legs of an internal transfer negative has its inbound leg (`TRANSFER…FROM` wording plus a negative amount) flipped to `:dest` (issue 222). Only the direction is overridden — the aggregator row stays a verbatim mirror and the ledger amount is stored as `.abs` either way. The override is gated on `negative?` so it is inert for correctly-signed feeds and self-heals if the provider fixes their signing. When it fires, `transaction_sources.direction_overridden` records it on the source attachment; that flag is written on create only and is never re-derived on resync.

### Production Database Setup

Production uses four separate PostgreSQL databases (Rails multi-DB):
- `honeyledger_production` — main app data
- `honeyledger_production_cache` — Solid Cache
- `honeyledger_production_queue` — Solid Queue
- `honeyledger_production_cable` — Solid Cable

Development uses a single database.

### Frontend

Turbo Frames for partial page updates, Turbo Streams for inline updates (e.g., `TransactionsController` index). Stimulus controllers in `app/javascript/controllers/`. Minimal custom JavaScript.

### Authorization Pattern

Controllers that expose user-owned financial data use `before_action :authenticate_user!`, and their queries are scoped to `current_user` to prevent cross-user data access. Some controllers are intentionally public (for example, `HomeController` and `CurrenciesController`) and do not require authentication because they only serve non-user-specific or informational data.

## Testing

- Framework: Minitest (not RSpec). Use `test "description" do ... end` syntax.
- Fixtures for test data; `minitest-mock` for mocking external dependencies.
- Coverage tracked with SimpleCov, uploaded to Codecov.
- Every item in a PR's test plan must have corresponding test coverage (unit, integration, or system test).
- **Layering:** controller tests (`test/controllers/*`) assert request flow only — `assert_response`, `assert_redirected_to`, controller-level branching. Anything about rendered content (text, row visibility, status tags, conditional rendering) belongs in `test/system/*` with Capybara matchers (`assert_text`, `assert_no_text`, scoped with `within(...)` for row-level checks). Don't `assert_match` against `response.body` in controller tests.
- **Coverage:** only the non-system `test` CI job uploads to Codecov; `system-test` does not. A Ruby line exercised only by a system test reads as uncovered and fails `codecov/patch`, so back every new or changed `.rb` branch with a model/controller/integration test as well.

## Code Conventions

- **Spell out variable names.** `simplefin_transaction`, not `sft`; `ledger_account`, not `la`. This applies to block parameters too (`do |transaction|`, not `do |t|`). A local named `transaction` is fine in services and jobs, but avoid it inside models and anything else that includes `ActiveRecord::Transactions`, where it would shadow a bare `transaction do … end` call — always call it with an explicit receiver (`Transaction.transaction do`) or pick another name there.
- **String/text columns** default to `default: "", null: false`. A column is nullable only when the upstream API spec genuinely permits the field to be null or omitted (for example Lunch Flow transaction `description`/`merchant`). When a required column is `null: false`, refresh/upsert writers must coalesce a missing upstream value with `.to_s` rather than assigning `nil` — the column default only applies when the attribute is unset. Existing mirror columns don't all follow this yet; the consistency pass is tracked in issue 161.
- **View links and buttons.** Two or more inline text `link_to`s on one line are separated by a literal ` | `. Two or more `button_to`s (or a `link_to` + `button_to` mix) in an actions cell go in a flex container with a small gap and no delimiter — `app/views/integrations/show.html.erb` is the canonical pattern. No middots, bullets, or slashes as separators.
- **Tables.** Match the transactions table's header treatment (`transactions.css` `.row.header`): title-case text, no `text-transform: uppercase`. A red (`var(--color-negative)`) Delete action is welcome.

## Privacy

Never put real user data into anything that lands in the repo or on GitHub: committed code, fixtures, test strings, commit messages, PR and issue bodies, review comments, or plan files. That covers financial-institution names, verbatim transaction descriptions (they carry merchant names, addresses, phone numbers, and partial account or card numbers), account-number fragments, and any other PII. Synthesize neutral placeholders instead (`"Test Bank"`, `"Sample Vendor"`, `"Long aggregator description that exceeds thirty-two characters"`) and describe the *shape* of a pattern rather than copying a literal example.

Naming a vendor as the *subject of an integration* — "support a provider's account-activity CSV export" — is fine; that's a product capability. Naming an institution or merchant *in the context of this user's own accounts or ledger data* is not. GitHub preserves edit history, so check before posting, not after.

## Git & PR Workflow

- **Review iterations:** address feedback with a fresh commit and a plain `git push`. Reserve `--amend` + `--force-with-lease` for rebasing onto an updated parent branch or explicit history cleanup — force-pushes refire CI and invalidate prior review state.
- **Commit subjects** describe the change and never carry `(#NN)` issue references (every force-push would re-fire a cross-reference event on the issue). Put a closing keyword once in the PR body — GitHub recognizes `close`/`closes`/`closed`, `fix`/`fixes`/`fixed`, and `resolve`/`resolves`/`resolved`, case-insensitively; each issue needs its own keyword (`Closes #10, fixes #12`), and the keyword only links when the PR targets `main`, so a stacked PR's keyword activates once it is retargeted. PR titles may reference issues.
- **Merging:** `gh pr merge --squash --delete-branch`, with the default subject so GitHub appends `(#PR)` itself. Passing `--subject` skips that suffix. If the title needs cleaning, `gh pr edit --title` first, then merge with the default. `--delete-branch` also removes the local branch and fast-forwards local `main`.
- **Stacked PRs:** before merging a parent with `--delete-branch`, run `gh pr edit <child> --base main` for every child further up the stack. GitHub auto-closes children whose base branch disappears, and a closed PR can neither be retargeted nor reopened.
- **Labels:** PRs and issues authored by an agent get `AI generated` plus a category. `enhancement` is strictly for user-visible features — ask "would a user notice this?"; if not, use `chore` (housekeeping, tooling, CI, renames) or `refactor` (internal restructuring with no behaviour change). `decision` marks a design or process question to settle before it becomes a work item; `bug`, `documentation`, `security`, and `question` keep their usual meaning. Apply labels once — either `--label` on create *or* `gh pr edit --add-label` afterwards, never both, since duplicate `labeled` timeline events cannot be removed. Never hand-apply `ruby`, `dependencies`, or `github_actions`; those belong to Dependabot and similar automation.
- **Priority and size** live on the "Honeyledger" GitHub Projects v2 board, not in repo labels: single-select fields **Priority** (P0 highest → P2) and **Size** (XS–XL), set with `gh api graphql` via `updateProjectV2ItemFieldValue` (requires the `project` token scope). Query the project, field, and option IDs at use time rather than hard-coding them.
- **Outbound writes** (issues, PR bodies, comments) are executed directly once asked for; present a draft first only when the request says so ("draft", "show me first", "review").

## GitHub Interaction

- **Bot reviewers** (Copilot, Codex, codecov) get replies, but as a one-way log: reply in the review thread with the decision and rationale, then stop. No "let me know if you disagree" — that phrasing is for humans.
- **Attribute judgment calls.** Comments post under the maintainer's account. Verifiable facts ("fixed in bdcffff, covered by …") can go in that voice; declining a finding or picking between defensible options cannot. Open such replies with an attribution line naming the agent as the author, present the trade-off as cost-versus-cost rather than a verdict, and offer to implement the alternative.
- **Commit SHAs** go bare in comments (`Fixed in bdcffff`) so GitHub auto-links them; backticks suppress the link. Keep backticks for code identifiers.
- **Bare `#N`** anywhere in issue/PR text creates a permanent backlink on item N. Only write it for an intentional reference — never as a list label (`(first)`, not `(#1)`).
- **`gh api --paginate`** on every list endpoint (`pulls/N/comments`, `pulls/N/reviews`, `issues/N/comments`). The default 30-item page silently truncates, and a truncated list looks complete.
- **Re-request bot reviews** after pushing fixes for their findings; neither bot re-reviews on push. Copilot: `gh api -X POST repos/{owner}/{repo}/pulls/N/requested_reviewers -f 'reviewers[]=copilot-pull-request-reviewer[bot]'` (the requested-reviewers list empties as soon as Copilot accepts, so an empty list is not a failed request). Codex: comment `@codex review` on the PR.
- **Copilot's login** differs by endpoint: `Copilot` on `pulls/N/comments`, `copilot-pull-request-reviewer[bot]` on `pulls/N/reviews`. Filter on both or match case-insensitively on `copilot`.

## Known Design Decisions

- Sources are many-to-many by design (`account_sources`, `transaction_sources`) with **first-writer-wins** for canonical fields. A per-account "primary source" and "most recent wins" were both considered and rejected; don't propose them without flagging that decision. A future "promote source" action is the intended escape hatch for a wrong first writer and is out of scope until asked for.
- "Duplicate transactions" means one of three distinct scenarios — pick the right one before proposing a fix: (1) an aggregator reissuing IDs for the same institution on reconnect, handled by `Transaction::Reconcile`'s exact matching; (2) switching a ledger account between aggregators (issue 115), unsolved and needing fuzzier matching because the feeds' descriptions and dates are not one-to-one; (3) stale aggregator-account rows cluttering the integrations page, handled by `last_seen_at` visibility thresholds.
- Empty revenue/expense accounts left behind after `Transaction::AutoMerge` reroutes an imported transaction are intentional merge references, not cleanup candidates. Don't file issues or propose removal; the account listing design is still settling.
- The Import Rules workbench deliberately has no enable/disable toggle and no rule-health stats (match counts, last matched). That was a schema-free visual rework. Adding them needs migrations plus tracking wired into the three `ImportTransactionsJob`s and `ImportRule::RetroactiveApply`.
- Issue 177: `Transaction::AutoMerge#absorb_into_existing_transfer` clones an existing transfer and orphans its source. Open and low priority. Any fix must not tell synthetic results from real ones via `transaction_sources.exists?` — `find_transfer_candidate` can match a manually created sourceless transfer, which `Transaction::Unmerge` would then destroy. Use an explicit synthetic-result marker set by `Transaction::Merge`.

## CI Checks (must pass before merging)

1. `bin/rubocop` — style
2. `bin/rails test` + `bin/rails test:system` — tests
3. `bin/brakeman --no-pager` — security
4. `bin/bundler-audit` + `bin/importmap audit` — dependency vulnerabilities
