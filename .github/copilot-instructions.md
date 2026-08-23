# Copilot Instructions for Honeyledger

## Project Overview
Honeyledger is a personal finance management application built with Ruby on Rails 8.1.2. It integrates with multiple bank data aggregator APIs — SimpleFIN and Lunch Flow — to automatically sync financial transactions from banks and other financial institutions, and supports double-entry bookkeeping.

## Core Technologies
- **Framework**: Ruby on Rails 8.1.2
- **Database**: PostgreSQL
- **Authentication**: Devise (~> 5.0.0.rc)
- **Frontend**: Hotwire (Turbo Rails + Stimulus)
- **Asset Pipeline**: Propshaft
- **Deployment**: Kamal (Docker-based deployment)
- **Testing**: Minitest with Capybara for system tests
- **Code Quality**: RuboCop with Rails Omakase styling

## Coding Standards

### Ruby Style Guide
- Follow the **Rails Omakase** style guide (configured via `.rubocop.yml`)
- Use RuboCop for linting: `bin/rubocop`
- Auto-fix style issues when possible: `bin/rubocop -a`
- All code must pass RuboCop checks before committing
- Spell out variable names (`simplefin_transaction`, not `sft`; `ledger_account`, not `la`). Abbreviations already in older code are grandfathered, but don't add new ones

### Rails Conventions
- Use Rails conventions for file structure and naming
- Models go in `app/models/`
- Controllers go in `app/controllers/`
- Views follow the `app/views/[controller]/[action].html.erb` pattern
- Use concerns for shared behavior (`app/models/concerns/`)
- Follow RESTful routing conventions

### Database
- Use PostgreSQL-specific features when beneficial
- Write database migrations carefully - they must be reversible
- Include appropriate indexes for foreign keys and frequently queried columns
- Use Active Record validations and associations
- String/text columns default to `default: "", null: false`; make a column nullable only when the upstream API spec genuinely permits the field to be null or omitted. Refresh/upsert writers coalesce missing upstream values with `.to_s` rather than assigning `nil` (the column default only applies when the attribute is unset). The consistency pass for existing mirror columns is tracked in issue 161

### Views
- Two or more inline text `link_to`s on one line are separated by a literal ` | `; adjacent `button_to`s go in a flex container with a small gap and no delimiter (see `app/views/integrations/show.html.erb`). No middots, bullets, or slashes as separators
- Tables match the transactions table's header treatment (`transactions.css` `.row.header`): title-case, no `text-transform: uppercase`. A red (`var(--color-negative)`) Delete action is fine

## Privacy

Never put real user data into anything that lands in the repo or on GitHub — code, fixtures, test strings, commit messages, PR and issue bodies, review comments. That covers financial-institution names, verbatim transaction descriptions (they carry merchant names, addresses, phone numbers, and partial account or card numbers), account-number fragments, and any other PII. Use neutral placeholders (`"Test Bank"`, `"Sample Vendor"`) and describe the shape of a pattern rather than copying a literal example. Naming a vendor as the subject of an integration (a provider's CSV export format) is fine; naming an institution or merchant in the context of the user's own accounts or ledger data is not. GitHub preserves edit history, so check before posting.

## Testing Practices

### Test Framework
- Use **Minitest** (not RSpec)
- All new features must include tests
- Test files go in `test/` directory matching the source structure:
  - `test/models/` for model tests
  - `test/controllers/` for controller tests
  - `test/system/` for system/integration tests
  - `test/helpers/` for helper tests

### Running Tests
- Run all tests: `bin/rails test`
- Run specific test file: `bin/rails test test/models/user_test.rb`
- Run system tests: `bin/rails test:system`

### Coverage
- Code coverage is tracked with SimpleCov
- Coverage reports are uploaded to Codecov
- Aim to maintain or improve coverage with new code
- Only the non-system `test` CI job uploads coverage; `system-test` does not. A Ruby line exercised only by a system test reads as uncovered and fails `codecov/patch`, so back every new or changed `.rb` branch with a model/controller/integration test

### Test Structure
- Use Minitest's default `test "description" do ... end` syntax
- Use fixtures for test data when appropriate
- Use `minitest-mock` for mocking external dependencies
- Layering: controller tests assert request flow only (`assert_response`, `assert_redirected_to`, controller-level branching). Rendered content — text, row visibility, status tags, conditional rendering — is tested in `test/system/*` with Capybara matchers (`assert_text`, `assert_no_text`, `within(...)`). Don't `assert_match` against `response.body` in controller tests

## Security Practices

### Security Tools
- **Brakeman**: Static analysis for security vulnerabilities
- **Bundler Audit**: Audits gems for known security defects
- Run security checks before committing: `bin/brakeman` and `bundle audit`

### Security Guidelines
- Never commit secrets, API keys, or credentials
- Use Rails credentials/secrets management for sensitive data
- Validate and sanitize all user inputs
- Use strong parameters in controllers
- Follow OWASP guidelines for web security

## Aggregator Integrations

Both SimpleFIN and Lunch Flow follow the same namespaced pattern: `Connection` → `Account` → `Transaction`, with a refresh job to sync from the API and a namespaced `ImportTransactionsJob` to create ledger transactions. Aggregator accounts link to ledger accounts through `account_sources`. Linking triggers `ImportTransactionsJob`, and refresh jobs automatically enqueue it for linked accounts after each successful account refresh. A unified `/integrations` page managed by `IntegrationsController` shows both connections and all aggregator accounts.

### SimpleFIN Integration

- **`lib/simplefin_client.rb`** (`SimplefinClient`) — HTTParty wrapper. `claim(token)` exchanges a setup token for a persistent access URL; `accounts(start_date:)` fetches raw account and transaction data.
- **`app/models/simplefin/`** — Three models:
  - `Simplefin::Connection` — Stores access URL (basic-auth credentials in URL) per user; `refresh` enqueues `Simplefin::RefreshJob`
  - `Simplefin::Account` — Raw account data; linked to a ledger `Account` through `account_sources`; `suggested_opening_balance` computes a starting balance from historical transactions
  - `Simplefin::Transaction` — Raw transaction records; `has_many :transaction_sources, as: :sourceable` and `has_many :ledger_transactions, through: :transaction_sources`
- **`Simplefin::RefreshJob`** — Upserts `Simplefin::Account` and `Simplefin::Transaction` records from the API

### Lunch Flow Integration

- **`lib/lunchflow_client.rb`** (`LunchflowClient`) — HTTParty wrapper with `x-api-key` header auth. `accounts` lists accounts; `balance(account_id)` and `transactions(account_id)` fetch per-account data. Raises `UnauthorizedError` on 401/403, `Error` on other failures.
- **`app/models/lunchflow/`** — Three models mirroring SimpleFIN:
  - `Lunchflow::Connection` — Stores API key per user; `refresh` enqueues `Lunchflow::RefreshJob`; `error` column stores API error messages
  - `Lunchflow::Account` — Raw account data with `institution_name`, `provider`, `status` (ACTIVE/ERROR/DISCONNECTED); linked to a ledger `Account` through `account_sources`
  - `Lunchflow::Transaction` — Raw transaction records with `merchant` field; linked to app `Transaction` through `transaction_sources`, like `Simplefin::Transaction`
- **`Lunchflow::RefreshJob`** — Fetches accounts, balances, and transactions per-account. Rescues `LunchflowClient::Error` and stores message on connection.

### Integration Patterns
- Use HTTParty for API requests to aggregators
- Handle API errors gracefully with proper error messages
- Respect API rate limits
- Store minimal sensitive data; use tokens/keys appropriately
- Each aggregator has a namespaced `ImportTransactionsJob` (`Simplefin::ImportTransactionsJob`, `Lunchflow::ImportTransactionsJob`): negative amount = expense (auto-creates expense account), positive = revenue; each requires a specific account ID

## Authentication & Authorization

### Devise
- User authentication is handled by Devise
- User model is in `app/models/user.rb`
- Customize Devise views in `app/views/devise/`
- Use `before_action :authenticate_user!` in controllers requiring authentication

### Authorization
- Ensure users can only access their own data
- Filter queries by `current_user` in controllers
- Use scopes in models to restrict data access

## Frontend Development

### Hotwire (Turbo + Stimulus)
- Use Turbo Frames for partial page updates
- Use Turbo Streams for real-time updates
- Keep JavaScript minimal with Stimulus controllers
- Stimulus controllers go in `app/javascript/controllers/`

### Assets
- CSS and JavaScript are managed via Propshaft
- Use import maps for JavaScript dependencies
- Keep assets organized in `app/assets/`

## Development Workflow

### Setup
- Prerequisites: Ruby (see `.ruby-version`), PostgreSQL
- Bootstrap: `bin/setup`
- Database: `bin/rails db:create db:migrate`
- Start server: `bin/dev`

### Code Quality Checks
Always run before committing:
1. `bin/rubocop` - Code style
2. `bin/rails test` - All tests
3. `bin/brakeman --no-pager` - Security scan
4. `bin/bundler-audit` - Dependency vulnerabilities
5. `bin/importmap audit` - JavaScript dependency vulnerabilities

### Deployment
- Application is deployed using Kamal
- Configuration in `.kamal/` directory
- Docker configuration in `Dockerfile`
- Deploy with: `kamal deploy`

## Models & Domain

### Domain Model (Double-Entry Bookkeeping)

Every `Transaction` has `src_account` and `dest_account` (both FK to `accounts`). Amounts are stored as integers in `amount_minor` (smallest currency unit). Account `balance_minor` is kept in sync via `after_save`/`after_destroy` callbacks using `update_counters` for atomic updates.

**`Account`** — `kind` enum: `asset`, `liability`, `equity`, `expense`, `revenue`. Accounts can be `real` (with currency and balance) or `virtual` (bookkeeping counterparts for opening balances).

**`Account`** links to aggregator accounts through `account_sources` (`has_many :account_sources`); each join row carries a polymorphic `sourceable` (`Simplefin::Account` or `Lunchflow::Account`). A ledger account may have several sources, but each aggregator account belongs to at most one ledger account (unique index on `sourceable_type, sourceable_id`). The `unlinked` scope finds accounts with no `account_sources`.

**`Transaction`** — Supports FX (`fx_amount_minor` + `fx_currency_id`), split transactions (`parent_transaction_id`, `split` flag), opening balances (`opening_balance` flag), and source tracking through `transaction_sources` (`has_many :transaction_sources`), whose polymorphic `sourceable` is a `Simplefin::Transaction`, `Lunchflow::Transaction`, or `Csv::Transaction`. Sources are many-to-many: one ledger transaction can carry rows from several feeds, while each source row attaches to exactly one ledger transaction. Canonical fields are first-writer-wins — later sources attach without overwriting. `Transaction::Reconcile` attaches an incoming source to an existing ledger transaction when amount, currency, a small date window, and a normalized description match, and abstains when the match is ambiguous.

### Core Models
- **User**: Application users (Devise)
- **Account**: User's financial accounts (manual or synced); links to aggregator accounts through `account_sources`
- **Transaction**: Financial transactions with double-entry bookkeeping
- **Category**: Transaction categories
- **Currency**: Supported currencies
- **Simplefin::Connection**: SimpleFIN API connections
- **Simplefin::Account**: Synced SimpleFIN accounts
- **Simplefin::Transaction**: Synced SimpleFIN transactions
- **Lunchflow::Connection**: Lunch Flow API connections
- **Lunchflow::Account**: Synced Lunch Flow accounts
- **Lunchflow::Transaction**: Synced Lunch Flow transactions

### Associations
- Users have many accounts, transactions, and connections (SimpleFIN and Lunch Flow)
- Accounts have many transactions
- Transactions belong to accounts and categories
- A ledger account can have several aggregator sources (`account_sources`); each aggregator account belongs to at most one ledger account
- A ledger transaction can have several source rows (`transaction_sources`, polymorphic `sourceable`); each source row belongs to exactly one ledger transaction

## Pull Request Guidelines

### Before Creating PR
- All tests pass
- RuboCop checks pass
- Security scans (Brakeman, Bundler Audit) pass
- Code coverage maintained or improved
- Commit messages are clear and descriptive

### PR Requirements
- Clear description of changes
- Reference related issues with a closing keyword once in the PR body (`Closes`, `Fixes`, or `Resolves` and their other forms; one keyword per issue, e.g. `Closes #10, fixes #12`). Keywords only link when the PR targets `main`
- Include screenshots for UI changes
- Update documentation if needed

### Commits, Merging, and Labels
- Commit subjects describe the change and never carry `(#NN)` issue references — every force-push would re-fire a cross-reference event on the issue
- Address review feedback with a fresh commit and a plain push; reserve `--amend` + force-push for rebasing onto an updated parent branch or explicit history cleanup
- Merge with `gh pr merge --squash --delete-branch` and the default subject so GitHub appends `(#PR)` itself; if the title needs cleaning, `gh pr edit --title` first
- Stacked PRs: retarget every child (`gh pr edit <child> --base main`) before merging the parent with `--delete-branch`; a child whose base branch disappears is auto-closed and cannot be reopened
- Agent-authored PRs and issues get `AI generated` plus a category label (`bug`, `enhancement`, `documentation`, `security`, …), applied once. Never hand-apply `ruby`, `dependencies`, or `github_actions` — those belong to Dependabot and similar automation
- Priority (P0–P2) and Size (XS–XL) are fields on the "Honeyledger" GitHub Projects v2 board, not repo labels

### GitHub Interaction
- Replies to bot reviewers (Copilot, Codex, codecov) are a one-way log in the review thread: decision and rationale, then stop — no invitations to discuss
- Write commit SHAs bare in comments so GitHub auto-links them; backticks suppress the link
- A bare `#N` anywhere in issue/PR text creates a permanent backlink on item N — only write it for an intentional reference, never as a list label
- Use `gh api --paginate` on every list endpoint; the default 30-item page silently truncates
- Copilot's login is `Copilot` on `pulls/N/comments` and `copilot-pull-request-reviewer[bot]` on `pulls/N/reviews`

### Known Design Decisions
- Empty revenue/expense accounts left behind after `Transaction::AutoMerge` are intentional merge references, not cleanup candidates
- The Import Rules workbench deliberately has no enable/disable toggle and no rule-health stats; adding them needs migrations plus tracking in the three `ImportTransactionsJob`s and `ImportRule::RetroactiveApply`
- Issue 177 (`Transaction::AutoMerge#absorb_into_existing_transfer` clones a transfer) is open and low priority; a fix must not tell synthetic results from real ones via `transaction_sources.exists?`, because a manually created sourceless transfer would be misclassified and destroyed by `Transaction::Unmerge`

## Common Tasks

### Adding a New Model
1. Generate: `bin/rails generate model ModelName`
2. Update migration as needed
3. Add validations and associations to model
4. Write model tests
5. Run migration: `bin/rails db:migrate`

### Adding a New Controller
1. Generate: `bin/rails generate controller ControllerName`
2. Define actions following RESTful conventions
3. Add authorization checks
4. Create corresponding views
5. Write controller tests

### Adding Dependencies
- Add gem to `Gemfile`
- Run `bundle install`
- Run `bundle audit` to check for vulnerabilities
- Document usage in this file if significant

## Troubleshooting

### Common Issues
- **Database errors**: Ensure PostgreSQL is running, try `bin/rails db:reset`
- **Asset issues**: Clear cache with `bin/rails assets:clobber`
- **Test failures**: Check fixtures and test database state

## Resources
- [Rails Guides](https://guides.rubyonrails.org/)
- [Rails Omakase Style Guide](https://github.com/rails/rubocop-rails-omakase/)
- [Devise Documentation](https://github.com/heartcombo/devise)
- [Hotwire Documentation](https://hotwired.dev/)
- [Kamal Documentation](https://kamal-deploy.org/)
