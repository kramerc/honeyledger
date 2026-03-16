# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Honeyledger is a personal finance management Rails 8.1.2 app that syncs financial transactions from banks via the SimpleFIN API and supports double-entry bookkeeping.

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
kamal deploy                                     # Deploy to production
```

## Architecture

### Domain Model (Double-Entry Bookkeeping)

Every `Transaction` has `src_account` and `dest_account` (both FK to `accounts`). Amounts are stored as integers in `amount_minor` (smallest currency unit). Account `balance_minor` is kept in sync via `after_save`/`after_destroy` callbacks using `update_counters` for atomic updates.

**`Account`** — `kind` enum: `asset`, `liability`, `equity`, `expense`, `revenue`. Accounts can be `real` (with currency and balance) or `virtual` (bookkeeping counterparts for opening balances).

**`Transaction`** — Supports FX (`fx_amount_minor` + `fx_currency_id`), split transactions (`parent_transaction_id`, `split` flag), opening balances (`opening_balance` flag), and source tracking via polymorphic `sourceable` → `Simplefin::Transaction`.

### `Minorable` Concern (`app/models/concerns/minorable.rb`)

Two class macros for handling minor-unit currency math:
- `minorable :amount, with: :currency` — computes read-only `amount_minor` from a decimal column scaled by `currency.decimal_places`
- `unminorable :amount_minor, with: :currency` — adds a read/write `amount` virtual attribute that converts to/from `amount_minor` via `before_save`, with deferred currency resolution

Used by `Transaction`, `Simplefin::Account`, and `Simplefin::Transaction`.

### SimpleFIN Integration Pipeline

1. **`lib/simplefin_client.rb`** (`SimplefinClient`) — HTTParty wrapper. `claim(token)` exchanges a setup token for a persistent access URL; `accounts(start_date:)` fetches raw account and transaction data.

2. **`app/models/simplefin/`** — Three models:
   - `Simplefin::Connection` — Stores access URL (basic-auth credentials in URL) per user; `refresh` enqueues `Simplefin::RefreshJob`
   - `Simplefin::Account` — Raw account data; optional `ledger_account_id` links to app `Account`; linking triggers `enqueue_import`; `suggested_opening_balance` computes a starting balance from historical transactions
   - `Simplefin::Transaction` — Raw transaction records linked to app `Transaction` via polymorphic `sourceable`

3. **Background jobs:**
   - `Simplefin::RefreshJob` — Upserts `Simplefin::Account` and `Simplefin::Transaction` records from the API
   - `TransactionImportJob` — Converts `Simplefin::Transaction` to app `Transaction`; negative amount = expense (auto-creates expense account by description), positive = revenue

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

## CI Checks (must pass before merging)

1. `bin/rubocop` — style
2. `bin/rails test` + `bin/rails test:system` — tests
3. `bin/brakeman --no-pager` — security
4. `bin/bundler-audit` + `bin/importmap audit` — dependency vulnerabilities
