# DESIGN.md

The visual and interaction design system for Honeyledger, written for coding agents (and people) building or changing UI. `AGENTS.md` covers how to work in this repository; this file covers how the interface should look and behave. Read it before touching a view, a stylesheet, or a Stimulus controller that changes what users see.

It describes what the app does today. When a change establishes a new pattern, update this file in the same pull request.

## Principles

- **A ledger first.** Honeyledger is a personal finance tool used to read and correct lists of transactions and accounts. Favour dense, scannable tables over cards and decoration. Numbers line up; rows keep a steady height.
- **Plain data until you reach for it.** Values read as text at rest. Affordances (outlines, carets, ghost placeholders) appear on hover or focus, not all the time.
- **Confirm or discard.** Editing happens in an explicit edit mode with Save and Cancel. Toggling Cleared is the one change that saves on click.
- **One boldness.** The honey palette carries the identity. Keep everything else quiet: no gradients except the header, no drop shadows on content, no decorative icons (see Icons for the functional ones).
- **Calm phones.** Phone layouts show fewer, larger things and stay read-only until the user asks to edit.

## Tokens

All colours are CSS custom properties on `:root` in `app/assets/stylesheets/application.css`. Theme-dependent tokens use `light-dark()`, and the theme follows the OS unless the user picks one with the header toggle, which sets `data-theme="light"` or `data-theme="dark"` on `<html>`. Never hard-code a colour that has a token, and never use `@media (prefers-color-scheme)`; `light-dark()` already handles both themes and the user override.

### Colour

| Token | Light | Dark | Use |
|---|---|---|---|
| `--honey` | `#F59E0B` | same | Hover borders, focus rings, the brand accent |
| `--honey-dark` | `#D97706` | same | Links, primary buttons, active markers |
| `--honey-deeper` | `#92400E` | same | Header gradient end, source badge text |
| `--honey-light` | `#FDE68A` | `#2D1C08` | Row hover, active sidebar link |
| `--honey-pale` | `#FEF9EE` | `#1E1408` | Table headers, sidebar, empty states |
| `--cream` | `#FFFDF7` | `#120D05` | Page and field backgrounds |
| `--bark` | `#1C1917` | `#FEF3C7` | Primary text |
| `--bark-medium` | `#44403C` | `#FDE68A` | Cell text, secondary text |
| `--bark-light` | `#78716C` | `#A16207` | Muted text, placeholders, arrows |
| `--divider` | `#F5E6C8` | `#3A2810` | Borders and rules |
| `--accent-text` | `#92400E` | `#FCD34D` | Header labels, form labels |
| `--color-positive` | `#15803D` | `#4ade80` | Money in, positive balances |
| `--color-negative` | `#DC2626` | `#f87171` | Money out, negative balances, Delete |

Feedback colours (`--color-success`, `--bg-success`, `--text-success`, and the `-error` set with `--border-error`) are for feedback only: flash messages, error panels, the CSV drop zone's status message, and the danger button's `--color-error` fill.

The transactions table adds three local tokens on `.transactions`:

- `--field-border`: field outlines. Full honey on the light theme; honey mixed 35% into the background on the dark theme, so a row of fields doesn't glare. Use it for any outlined field or hover outline in the table.
- `--cell-edit-height`: `calc(1.4em + 8px)`, the shared height of editable cells and edit-form fields, so rows keep their height in edit mode.
- `--cell-edit-caret`: the honey ▾ used on list-backed fields.

### Type

- One family: the system UI stack on `body` (`-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, …`). Don't add web fonts.
- Base size 14px, line height 1.5.
- Scale in use: `1.25rem` header title; `1rem` phone row titles and amounts; `0.875rem` table cells and body copy; `0.8rem` actions, buttons, the transaction type indicator, secondary details; `0.75rem` table headers and form labels; `0.7rem` badges.
- Weights: 400 body, 600 headers, labels, and buttons, 700 the header title.
- Numbers: `font-variant-numeric: tabular-nums` and right alignment in numeric columns (`.numeric`).
- Case: sentence case for copy and buttons, title case for table headers, never `text-transform: uppercase` in tables. The sidebar's small group labels are the one existing uppercase treatment; don't extend it.

### Shape and spacing

- Radius: 4px for fields, buttons, and hover outlines; 8px for containers (tables, flashes, empty states, error panels); 3px for badges.
- Cell padding 7px 10px. Page padding 20px 24px on desktop, 12px on phones.
- Borders are 1px `--divider`. Emphasis uses `--honey` borders, not thicker lines.

### Motion

Transitions only answer the user (hover, open, close) and stay short: 0.1–0.2s on colour, border, or transform. Wrap any non-trivial transition in a `prefers-reduced-motion: reduce` override. No entrance animations.

## Layout

- **Shell:** a sticky 60px header with the honey gradient, a resizable sidebar (`--sidebar-width`, default 200px), and `main`. `main` has `min-width: 0`, so wide content scrolls inside its own container or truncates instead of widening the page.
- **Breakpoints:**
  - `< 768px`: the sidebar becomes an off-canvas drawer behind the hamburger button; account and settings tables collapse to cards.
  - `< 1024px`: the transactions table switches to phone rows (below).
  - `1024–1279px`: the transactions table hides Description, Currency, Category, and Cleared.
  - `≥ 1280px`: the full transactions table.
- Every page must work at 390px wide with no horizontal page scroll; only a wide table may scroll inside its own box.

## Components

### Tables

The main data tables (transactions, accounts, passkeys) are CSS grids of `.row` elements: one grid template per table, cells as `div`s, header row first, collapsing to cards or phone rows below their breakpoint. The rules below describe those. Integrations, Import Rules (the list and its previews), and the CSV import screens use native `<table>` markup; that is fine as it is and doesn't need converting, though a new data table that collapses on phones should use the grid pattern.

- Header row (`.row.header`): `--honey-pale` background, `0.75rem`, weight 600, `--accent-text`, title case. Sticky on the transactions table.
- Cells: 1px right and bottom `--divider` borders, `--bark-medium` text at `0.875rem`.
- Row hover (desktop only): `--honey-light` background.
- Long text (description, account names): one line with an ellipsis, the full text in `title`.
- Actions cell (transactions): icons only, with no visible header (the word "Actions" stays for screen readers). The column (`--actions-column`) is one icon button wide plus padding, and widens to two buttons only while a row is being edited (`.transactions:has(.transaction.editing)`); both widths derive from the button size, so the icons fill the cell exactly. Opening an edit shifts the other columns slightly; that is the accepted cost of not reserving the room. A shown row has its kebab menu (see Action menus); the new-transaction and edit form rows have their icon form actions (see Buttons).

### Links and action clusters

- Two or more inline text links on one line are separated by a literal ` | `.
- Two or more buttons (or a link mixed with a `button_to`) sit in a flex container with a small gap and no delimiter; `app/views/integrations/show.html.erb` is the reference.
- No middots, bullets, or slashes as separators, and no `→` appended to link text.

### Icons

Icons are functional only: they stand in for a control's label where a word won't fit, never decorate. The set is [Lucide](https://lucide.dev), through the `lucide-rails` gem, whose `lucide_icon "name", size: 16` helper inlines the SVG with `stroke="currentColor"` and `aria-hidden="true"`. The icon files ship inside the gem; don't copy third-party SVGs into `app/assets`.

- Size 16px inside the table and other dense UI.
- Colour comes from the control's `color`, so an icon follows its control's hover and theme states; never fill or stroke an icon with a literal colour.
- An icon-only control carries an `aria-label` naming what it does (see Accessibility).
- In use: `ellipsis-vertical` (the action-menu trigger); `plus`, `check`, and `x` (Create, Save, and Cancel in the transactions table).

### Action menus

A row with several actions puts them behind a kebab trigger (`menu-trigger`, `lucide_icon "ellipsis-vertical"`) that opens a popover menu (`menu`, `menu_controller.js`, styles in `menu.css`). The transactions table is the reference.

- Built on the Popover API: the menu is in the top layer, so the table's scroll box can't clip it. The browser closes it on an outside click or Escape; Escape (and Tab, or choosing an item that leaves the trigger visible) returns focus to the trigger, while an outside click leaves focus where the user clicked. The app requires a browser with the Popover API (Firefox 125+, via `allow_browser` in `ApplicationController`). CSS anchor positioning right-aligns it under the trigger, flipping above near the bottom of the window, before its first paint, so it never opens in one place and jumps to another; the view pairs the two with a per-row `anchor-name` / `position-anchor`. Don't position menus from the `toggle` event, which fires after the paint. Anchor placement needs both `anchor-name` and `position-try-fallbacks` (older Chromium can anchor but not flip); where either is missing, the controller places the menu by script, hidden until placed, and `menu.css` and the controller test for the same pair. The controller also closes the menu on scroll, focuses the first item on open (without scrolling, which would close it), moves between items with the arrow keys, Home, and End, activates the focused item on Space as well as Enter, and closes it once an item is chosen. An item that hides the trigger (Edit) moves focus to where the user goes next, here the edit form's first field.
- Markup: the trigger is a `<button type="button" popovertarget=…>` with `aria-haspopup="menu"`, `aria-expanded`, and an `aria-label`; the menu is `role="menu"` and each action a `role="menuitem"` link that keeps its own Turbo or Stimulus behaviour (confirmations included).
- Trigger: the same square as the form's icon buttons (`--action-button-size`, falling back to 28px outside the transactions table; 36px on phones), so the kebab lines up with Create and Save in the column; `--bark-light` at rest; on hover (only where the device can hover, since touch screens keep `:hover` after a tap) or while open, a `--field-border` outline, `--cream` fill, and `--honey-dark` icon.
- Menu: `--cream`, 1px `--divider` border, 8px radius, and a soft shadow, the one floating surface besides the form error panel. Items are `0.875rem` `--bark-medium` text (`1rem` with taller rows on phones) with a `--honey-light` hover and focus; keyboard focus adds the standard 2px honey ring, inset, since the tint alone barely shows on the dark theme.
- Order: the everyday action first (Edit), then state changes (Exclude or Restore, Unmerge), then a divider and Delete in `--color-negative`, always last.
- Only actions that apply to the row are listed; don't show disabled items.

### Buttons

The selection bar's buttons (`.selection-bar__btn`, in `transactions.css`) are the reference set:

- **Primary:** `--honey-dark` fill, white weight-600 text, hover `--honey`.
- **Secondary:** an outlined button: transparent with a `--divider` border and `--bark-medium` text, hover `--honey-light`. In the transactions edit form, Cancel carries its own `--cream` fill and, on hover, a `--field-border` border with a `--honey-pale` fill, because the row behind it is often honey-tinted.
- **Danger:** `--color-error` fill, white text.

In forms, the confirming action is primary and Cancel is secondary, at the same size; give the primary a transparent 1px border so the two match in height. On phones they keep these styles.

**Icon form actions.** In the transactions table's form rows, Create, Save, and Cancel are square icon buttons (`.form-action`, `--primary` / `--secondary`) at `--action-button-size` (the edit fields' height, in rem; the column is sized from the same value) on desktop, so the Actions column stays narrow: `plus` for Create, `check` for Save, `x` for Cancel. Each keeps its word in a `.form-action__label` span, which is the accessible name (visually hidden on desktop), and a matching `title` for the tooltip. Below 1024px the icon hides and the word shows, so phones keep worded buttons. Enter submits and Escape cancels, as before.

### Editable cells (transactions table)

The pattern for changing a value in place on desktop:

1. Each editable value renders as `<button class="cell-edit">` that looks like plain cell text (`TransactionsHelper#edit_field_button`).
2. On hover or focus it gains a 1px `--field-border` outline, a `--cream` background, and, for list-backed fields (accounts, category), the honey caret. An empty value shows a muted italic placeholder such as "Add category".
3. Clicking it opens the row's edit form with that field focused (`transactions--row#editField`). Resting the pointer on a cell for 250ms preloads the form; a pointer sweeping across rows loads nothing.
4. The edit form replaces the row in place. Its fields take the hovered-cell look at the same height and offset (`--cell-edit-height`), and the row's read-only badges stay visible, so the row's height and the positions of its values don't change.
5. Save confirms; Cancel or Escape discards. An Escape that closes an open list only closes the list.

Rules that came with it:

- Cell buttons are a mouse shortcut and carry `tabindex="-1"`, so a keyboard doesn't pass through every cell of every row. Only do this when an equivalent keyboard path exists (here, the Edit item in the row's action menu and the form's own fields).
- Toggling Cleared saves at once with a PATCH of just that field (`button_to`, `aria-pressed`). If the server rejects it, edit mode opens to show the errors.
- Opening balances and virtual accounts are never editable inline; they render as plain text.

### Type indicator and badges

- **Transaction type** (`.tx-type`): coloured text, not a pill: an arrow and a word ("↓ Withdrawal", "↑ Deposit", "⇄ Transfer") at `0.8rem`, weight 600, with no background or border. Deposits and refunds use `--color-positive`, withdrawals and clawbacks `--color-negative`, transfers `--bark-light`.
- **Source badges** (`.source-badge--simplefin`, `--lunchflow`, `--csv`): 3px radius, 1px `currentColor` border, under the date.
- **Status badges** (`.excluded-badge`, `.merged-badge`): outlined, 3px radius, beside the type. Merged is a link in the row that toggles the merged details; it is plain text in the edit form.

### Forms

- Labels are visually hidden in table rows (still present for screen readers) and shown above each field on phones, in `--accent-text` at `0.75rem`.
- Field look on desktop: as described under editable cells. On phones: full width, `1rem` text (which also keeps iOS from zooming on focus), 8px 10px padding, `--field-border` outline.
- Validation errors appear in a panel with `--bg-error`, a 4px `--color-error` left border, and an 8px radius, listing each message.

### Flash messages and empty states

- Flashes: an 8px-radius panel with a 4px left border in the feedback colour, dismissible.
- Empty states: `--honey-pale` panel, 8px radius, centred, with the next action as a link. Treat emptiness as a prompt to act, not a mood.

## Phones

- Transaction rows are three lines: description and amount; From → To; then date, cleared, type, and category with the action-menu trigger on the right. Empty Category and Cleared are hidden.
- Rows are read-only until the user chooses Edit. Interactive controls are hidden with `display: none` behind a plain-text twin (`.cell-static`), which removes them from taps, the Tab order, and assistive technology. Don't rely on `pointer-events: none` to make something read-only.
- The edit form sits in the list like a row: no surrounding box, a divider underneath.
- The new-transaction form is folded behind a "New transaction" button (`disclosure` controller).

## Accessibility

- Every control is reachable by keyboard, except a mouse shortcut that duplicates a reachable path (and then it says so in a comment).
- Visible focus: a 2px honey ring (`color-mix` at 45%) with a 1px offset on custom controls.
- Give icon-only and value-only buttons an accessible name (`aria-label`), and toggles `aria-pressed`.
- Colour is never the only signal: the type indicator carries words and arrows, and balances carry signs.
- Check contrast in both themes; the dark theme mutes borders, not text.

## Copy

Write for the person managing their money, in plain words and sentence case. Buttons say what happens ("Save", "Create", "Mark as cleared"), and the same action keeps the same name throughout. Errors say what went wrong and how to fix it, without apologising. Never put real institution names, merchant strings, or account numbers in examples, placeholders, or tests (see "Privacy" in `AGENTS.md`).

## Verifying UI changes

- Rendered behaviour belongs in system tests (`test/system/*`), per `AGENTS.md`.
- Look at the result before calling it done: screenshot at 390px and around 1400px, in both themes, including any hover and edit states you changed.
- Check that rows keep their height when entering edit mode, that nothing scrolls the page sideways at 390px, and that phones stay read-only.
