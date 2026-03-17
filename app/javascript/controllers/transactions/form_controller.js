import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "srcAccount", "destAccount", "type", "amount", "currency", "error" ]
  static values = { accountName: String }
  static TYPE_CONFIG = {
    withdrawal: { label: "↓ Withdrawal", class: "tx-type tx-type--withdrawal" },
    deposit:    { label: "↑ Deposit",    class: "tx-type tx-type--deposit" },
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

  updateEnabledAccounts(resetInvalidFields = true) {
    if (!this.hasSrcAccountTarget || !this.hasDestAccountTarget) return

    const { id: srcId, kind: srcKind } = this.selectedAccount(this.srcAccountTarget)
    const { id: destId, kind: destKind } = this.selectedAccount(this.destAccountTarget)
    const srcOptions = this.srcAccountTarget.options
    const destOptions = this.destAccountTarget.options

    /*
      Disable options that would create invalid transactions:
      - Source and destination accounts cannot be the same
      - Cannot transact from a revenue account to an expense account
      - Cannot transact from an expense account to a revenue account
    */
    for (const option of srcOptions) {
      const sameId = option.value !== "" && option.value === destId
      const incompatibleKind = destKind === "expense" && option.dataset.kind === "revenue"
      option.disabled = sameId || incompatibleKind
      if (resetInvalidFields && option.disabled && option.selected) {
        this.srcAccountTarget.selectedIndex = 0
      }
    }
    for (const option of destOptions) {
      const sameId = option.value !== "" && option.value === srcId
      const incompatibleKind = srcKind === "revenue" && option.dataset.kind === "expense"
      option.disabled = sameId || incompatibleKind
      if (resetInvalidFields && option.disabled && option.selected) {
        this.destAccountTarget.selectedIndex = 0
      }
    }
  }

  updateCurrency() {
    if (!this.hasDestAccountTarget || !this.hasCurrencyTarget) return

    const select = this.destAccountTarget
    const option = select.options[select.selectedIndex]
    const currency = option ? option.dataset.currency || "" : ""
    this.currencyTarget.textContent = currency || "—"
  }

  updateTypeFromSelectedAccounts() {
    if (!this.hasSrcAccountTarget || !this.hasDestAccountTarget) return

    const { kind: srcKind } = this.selectedAccount(this.srcAccountTarget)
    const { kind: destKind } = this.selectedAccount(this.destAccountTarget)

    let type = undefined
    if (destKind === "expense") {
      type = "withdrawal"
    } else if (srcKind === "revenue") {
      type = "deposit"
    } else if (srcKind && destKind) {
      type = "transfer"
    }

    this.updateTypeTarget(type)
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
