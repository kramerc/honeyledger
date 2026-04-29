import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "anchorAccount", "counterpartyAccount", "type", "amount", "currency", "error" ]
  static TYPE_CONFIG = {
    withdrawal: { label: "↓ Withdrawal", class: "tx-type tx-type--withdrawal" },
    refund:     { label: "↑ Refund",     class: "tx-type tx-type--refund" },
    deposit:    { label: "↑ Deposit",    class: "tx-type tx-type--deposit" },
    clawback:   { label: "↓ Clawback",   class: "tx-type tx-type--clawback" },
    transfer:   { label: "⇄ Transfer",  class: "tx-type tx-type--transfer" }
  }

  connect() {
    this.updateEnabledAccounts(false)
    this.updateCurrency()
    this.updateTypeFromSelectedAccounts()
  }

  clearError() {
    if (this.hasErrorTarget) {
      this.errorTarget.remove()
    }
  }

  // Filter the counterparty options based on the anchor's kind. The model
  // requires that any income/expense side pair with a balance-sheet account, so
  // when the anchor is itself income/expense the counterparty must be balance-sheet.
  updateEnabledAccounts(resetInvalidFields = true) {
    if (!this.hasCounterpartyAccountTarget) return

    const anchor = this.anchor()
    const counterpartyOptions = this.counterpartyAccountTarget.options

    const isIncomeExpense = (kind) => kind === "expense" || kind === "revenue"

    for (const option of counterpartyOptions) {
      if (option.value === "") continue
      const sameId = option.value === anchor.id
      const incompatibleKind = isIncomeExpense(anchor.kind) && isIncomeExpense(option.dataset.kind)
      option.disabled = sameId || incompatibleKind
      if (resetInvalidFields && option.disabled && option.selected) {
        this.counterpartyAccountTarget.selectedIndex = 0
      }
    }
  }

  // Currency follows the anchor (the balance-sheet side that owns the balance).
  updateCurrency() {
    if (!this.hasCurrencyTarget) return

    const anchor = this.anchor()
    this.currencyTarget.textContent = anchor.currency || "—"
  }

  updateTypeFromSelectedAccounts() {
    if (!this.hasCounterpartyAccountTarget) return

    const anchor = this.anchor()
    const counterparty = this.selectedAccount(this.counterpartyAccountTarget)
    const direction = this.directionValue()

    // Resolve src/dest from anchor + direction, then run the same kind-pair
    // mapping the server-side helper uses.
    let srcKind, destKind
    if (direction === "in") {
      srcKind = counterparty.kind
      destKind = anchor.kind
    } else {
      srcKind = anchor.kind
      destKind = counterparty.kind
    }

    const isBalanceSheet = (kind) => !!kind && kind !== "expense" && kind !== "revenue"

    let type = undefined
    if (isBalanceSheet(srcKind) && destKind === "expense") {
      type = "withdrawal"
    } else if (srcKind === "expense" && isBalanceSheet(destKind)) {
      type = "refund"
    } else if (srcKind === "revenue" && isBalanceSheet(destKind)) {
      type = "deposit"
    } else if (isBalanceSheet(srcKind) && destKind === "revenue") {
      type = "clawback"
    } else if (srcKind && destKind) {
      type = "transfer"
    }

    this.updateTypeTarget(type)
  }

  // Anchor target is either a select (unfiltered view) or a hidden input
  // (account-scoped view). For the hidden case we read kind/currency from
  // data attributes on the input so the controller has the same metadata.
  anchor() {
    if (!this.hasAnchorAccountTarget) return { id: undefined, kind: undefined, currency: undefined }

    const target = this.anchorAccountTarget
    if (target.tagName === "SELECT") {
      return this.selectedAccount(target)
    }
    return {
      id: target.value,
      kind: target.dataset.kind || undefined,
      currency: target.dataset.currency || undefined
    }
  }

  // Direction is inferred from the amount field's sign: a leading "-" means
  // outflow; positive (with or without "+") means inflow; blank defaults to
  // outflow to match the controller's fallback.
  directionValue() {
    if (!this.hasAmountTarget) return "out"
    const value = this.amountTarget.value.trim()
    if (value === "") return "out"
    if (value.startsWith("-")) return "out"
    return "in"
  }

  selectedAccount(select) {
    const option = select.options[select.selectedIndex]
    if (!option) {
      return { id: undefined, kind: undefined, currency: undefined }
    }
    return {
      id: option.value,
      kind: option.dataset.kind || undefined,
      currency: option.dataset.currency || undefined
    }
  }

  updateTypeTarget(type) {
    if (!this.hasTypeTarget) return

    const config = this.constructor.TYPE_CONFIG[type]
    this.typeTarget.textContent = config ? config.label : ""
    this.typeTarget.className = config ? config.class : ""
  }
}
