import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "srcAccount", "destAccount", "type", "currency", "error" ]

  connect() {
    this.updateEnabledAccounts(false)
    this.updateCurrency()
    this.updateType()
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
    this.currencyTarget.textContent = currency
  }

  updateType() {
    if (!this.hasSrcAccountTarget || !this.hasDestAccountTarget || !this.hasTypeTarget) return

    const { kind: srcKind } = this.selectedAccount(this.srcAccountTarget)
    const { kind: destKind } = this.selectedAccount(this.destAccountTarget)

    let label = ""
    let color = "gray"

    if (destKind === "expense") {
      label = "↓ Withdrawal"
      color = "red"
    } else if (srcKind === "revenue") {
      label = "↑ Deposit"
      color = "green"
    } else if (srcKind && destKind) {
      label = "⇄ Transfer"
      color = "gray"
    }

    this.typeTarget.textContent = label
    this.typeTarget.style.color = color
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
}
