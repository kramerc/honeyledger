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

### Test Structure
- Use Minitest's default `test "description" do ... end` syntax
- Use fixtures for test data when appropriate
- Use `minitest-mock` for mocking external dependencies

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

Both SimpleFIN and Lunch Flow follow the same namespaced pattern: `Connection` → `Account` → `Transaction`, with a refresh job to sync from the API and a namespaced `ImportTransactionsJob` to create ledger transactions. Aggregator accounts link to ledger accounts via the polymorphic `Account#sourceable`. Linking triggers `ImportTransactionsJob`, and refresh jobs automatically enqueue it for linked accounts after each successful account refresh. A unified `/integrations` page managed by `IntegrationsController` shows both connections and all aggregator accounts.

### SimpleFIN Integration

- **`lib/simplefin_client.rb`** (`SimplefinClient`) — HTTParty wrapper. `claim(token)` exchanges a setup token for a persistent access URL; `accounts(start_date:)` fetches raw account and transaction data.
- **`app/models/simplefin/`** — Three models:
  - `Simplefin::Connection` — Stores access URL (basic-auth credentials in URL) per user; `refresh` enqueues `Simplefin::RefreshJob`
  - `Simplefin::Account` — Raw account data; `has_one :ledger_account, as: :sourceable`; `suggested_opening_balance` computes a starting balance from historical transactions
  - `Simplefin::Transaction` — Raw transaction records linked to app `Transaction` via polymorphic `sourceable`
- **`Simplefin::RefreshJob`** — Upserts `Simplefin::Account` and `Simplefin::Transaction` records from the API

### Lunch Flow Integration

- **`lib/lunchflow_client.rb`** (`LunchflowClient`) — HTTParty wrapper with `x-api-key` header auth. `accounts` lists accounts; `balance(account_id)` and `transactions(account_id)` fetch per-account data. Raises `UnauthorizedError` on 401/403, `Error` on other failures.
- **`app/models/lunchflow/`** — Three models mirroring SimpleFIN:
  - `Lunchflow::Connection` — Stores API key per user; `refresh` enqueues `Lunchflow::RefreshJob`; `error` column stores API error messages
  - `Lunchflow::Account` — Raw account data with `institution_name`, `provider`, `status` (ACTIVE/ERROR/DISCONNECTED); `has_one :ledger_account, as: :sourceable`
  - `Lunchflow::Transaction` — Raw transaction records with `merchant` field; linked to app `Transaction` via polymorphic `sourceable`
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

**`Account`** also has a polymorphic `sourceable` linking it to an aggregator account (`Simplefin::Account` or `Lunchflow::Account`). A unique index enforces one source per ledger account. The `unlinked` scope finds accounts with no aggregator link.

**`Transaction`** — Supports FX (`fx_amount_minor` + `fx_currency_id`), split transactions (`parent_transaction_id`, `split` flag), opening balances (`opening_balance` flag), and source tracking via polymorphic `sourceable` → `Simplefin::Transaction` or `Lunchflow::Transaction`.

### Core Models
- **User**: Application users (Devise)
- **Account**: User's financial accounts (manual or synced); links to an aggregator via polymorphic `sourceable`
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
- A ledger account links to at most one aggregator account via polymorphic `sourceable`

## Pull Request Guidelines

### Before Creating PR
- All tests pass
- RuboCop checks pass
- Security scans (Brakeman, Bundler Audit) pass
- Code coverage maintained or improved
- Commit messages are clear and descriptive

### PR Requirements
- Clear description of changes
- Reference related issues
- Include screenshots for UI changes
- Update documentation if needed

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
