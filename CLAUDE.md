# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Honeyledger is a personal finance management Rails 8.1.2 app that syncs financial transactions from banks via aggregator APIs (SimpleFIN and Lunch Flow) and supports double-entry bookkeeping.

**Stack:** Ruby on Rails 8.1.2, PostgreSQL, Devise, Hotwire (Turbo + Stimulus), Propshaft + importmap, Minitest, Kamal deployment.

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
bin/worktree-clean --drop                        # Drop databases left by deleted worktrees
kamal deploy                                     # Deploy to production
```

## Parallel Development

Several Claude Code sessions and agents work this repo at once. Each concurrent
line of work gets its own git worktree, and each worktree is isolated so that
sessions never share a database, a port, or a branch.

**Start isolated work in a worktree**, not in the primary checkout — use the
`EnterWorktree` tool, or `git worktree add .claude/worktrees/<name> -b <branch>`.
Reserve the primary checkout at `/home/kramer/Dev/Honeyledger/honeyledger` for
review, merging, and anything that must see `main`.

**What is isolated automatically:**

- **Databases.** `config/database.yml` appends a per-worktree suffix to the
  development and test database names (`honeyledger_test_<worktree>`), derived
  from the worktree directory. The primary checkout keeps the plain, unsuffixed
  names. Two sessions can run `bin/rails test` simultaneously without clobbering
  each other's fixtures, and a migration on one branch cannot break another.
  Override with `HONEYLEDGER_DB_SUFFIX`; production is never suffixed.
- **Secrets and local settings.** `bin/worktree-setup` runs as a `SessionStart`
  hook. In a worktree it symlinks the gitignored `config/master.key` and
  `.claude/settings.local.json` from the primary checkout and prepares that
  worktree's databases. It is idempotent and a no-op in the primary checkout.
- **Ports.** `bin/dev` claims the first free port at or above 3000, so servers
  from different worktrees coexist. Set `PORT` to pin one.
- **Logs, tmp, and coverage** are per-worktree already.

**What is still shared** — coordinate before touching these: the `main` branch
and remote, the `honeyledger_development` database in the primary checkout, and
any real aggregator API credentials.

**Cleaning up.** `git worktree remove` does not drop the databases the worktree
created. Run `bin/worktree-clean` to list orphaned databases and
`bin/worktree-clean --drop` to reclaim them.

Test parallelism within a single worktree stays disabled (see
`test/test_helper.rb`) because it conflicts with SimpleCov; with several
sessions running suites concurrently the cores are better spent across
worktrees anyway.

## Architecture

### Domain Model (Double-Entry Bookkeeping)

Every `Transaction` has `src_account` and `dest_account` (both FK to `accounts`). Amounts are stored as integers in `amount_minor` (smallest currency unit). Account `balance_minor` is kept in sync via `after_save`/`after_destroy` callbacks using `update_counters` for atomic updates.

**`Account`** — `kind` enum: `asset`, `liability`, `equity`, `expense`, `revenue`. Accounts can be `real` (with currency and balance) or `virtual` (bookkeeping counterparts for opening balances).

**`Account`** also has a polymorphic `sourceable` linking it to an aggregator account (`Simplefin::Account` or `Lunchflow::Account`). A unique index enforces one source per ledger account. The `unlinked` scope finds accounts with no aggregator link.

**`Transaction`** — Supports FX (`fx_amount_minor` + `fx_currency_id`), split transactions (`parent_transaction_id`, `split` flag), opening balances (`opening_balance` flag), and source tracking via polymorphic `sourceable` → `Simplefin::Transaction` or `Lunchflow::Transaction`.

### `Minorable` Concern (`app/models/concerns/minorable.rb`)

Two class macros for handling minor-unit currency math:
- `minorable :amount, with: :currency` — computes read-only `amount_minor` from a decimal column scaled by `currency.decimal_places`
- `unminorable :amount_minor, with: :currency` — adds a read/write `amount` virtual attribute that converts to/from `amount_minor` via `before_save`, with deferred currency resolution

Used by `Transaction`, `Simplefin::Account`, `Simplefin::Transaction`, `Lunchflow::Account`, and `Lunchflow::Transaction`.

### Aggregator Integration Pattern

Both SimpleFIN and Lunch Flow follow the same namespaced pattern: `Connection` → `Account` → `Transaction`, with a refresh job to sync from the API and a namespaced `ImportTransactionsJob` to create ledger transactions. Aggregator accounts link to ledger accounts via the polymorphic `Account.sourceable`. Linking triggers `ImportTransactionsJob`, and refresh jobs automatically enqueue it for linked accounts after each successful account refresh. A unified `/integrations` page managed by `IntegrationsController` shows both connections and all aggregator accounts.

### SimpleFIN Integration

1. **`lib/simplefin_client.rb`** (`SimplefinClient`) — HTTParty wrapper. `claim(token)` exchanges a setup token for a persistent access URL; `accounts(start_date:)` fetches raw account and transaction data.

2. **`app/models/simplefin/`** — Three models:
   - `Simplefin::Connection` — Stores access URL (basic-auth credentials in URL) per user; `refresh` enqueues `Simplefin::RefreshJob`
   - `Simplefin::Account` — Raw account data; `has_one :ledger_account, as: :sourceable`; `suggested_opening_balance` computes a starting balance from historical transactions
   - `Simplefin::Transaction` — Raw transaction records linked to app `Transaction` via polymorphic `sourceable`

3. **`Simplefin::RefreshJob`** — Upserts `Simplefin::Account` and `Simplefin::Transaction` records from the API

### Lunch Flow Integration

1. **`lib/lunchflow_client.rb`** (`LunchflowClient`) — HTTParty wrapper with `x-api-key` header auth. `accounts` lists accounts; `balance(account_id)` and `transactions(account_id)` fetch per-account data. Raises `UnauthorizedError` on 401/403, `Error` on other failures.

2. **`app/models/lunchflow/`** — Three models mirroring SimpleFIN:
   - `Lunchflow::Connection` — Stores API key per user; `refresh` enqueues `Lunchflow::RefreshJob`; `error` column stores API error messages
   - `Lunchflow::Account` — Raw account data with `institution_name`, `provider`, `status` (ACTIVE/ERROR/DISCONNECTED); `has_one :ledger_account, as: :sourceable`
   - `Lunchflow::Transaction` — Raw transaction records with `merchant` field; linked to app `Transaction` via polymorphic `sourceable`

3. **`Lunchflow::RefreshJob`** — Fetches accounts, balances, and transactions per-account. Rescues `LunchflowClient::Error` and stores message on connection.

### ImportTransactionsJob

Each aggregator namespace has its own `ImportTransactionsJob` (`Simplefin::ImportTransactionsJob`, `Lunchflow::ImportTransactionsJob`) that converts aggregator transactions to app `Transaction` records with double-entry bookkeeping. Negative amount = expense (auto-creates expense account), positive = revenue. Lunch Flow imports prefer `merchant` over `description`. Each job requires a specific account ID. RefreshJobs automatically enqueue import jobs for linked accounts after a successful per-account refresh.

Direction is not derived from the sign alone. `Transaction::InferLedgerSide` (`app/services/transaction/infer_ledger_side.rb`) applies one override on top of it: a feed that signs *both* legs of an internal transfer negative has its inbound leg (`TRANSFER…FROM` wording plus a negative amount) flipped to `:dest` (#222). Only the direction is overridden — the aggregator row stays a verbatim mirror and the ledger amount is stored as `.abs` either way. The override is gated on `negative?` so it is inert for correctly-signed feeds and self-heals if the provider fixes their signing. When it fires, `transaction_sources.direction_overridden` records it on the source attachment; that flag is written on create only and is never re-derived on resync.

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

## CI Checks (must pass before merging)

1. `bin/rubocop` — style
2. `bin/rails test` + `bin/rails test:system` — tests
3. `bin/brakeman --no-pager` — security
4. `bin/bundler-audit` + `bin/importmap audit` — dependency vulnerabilities
