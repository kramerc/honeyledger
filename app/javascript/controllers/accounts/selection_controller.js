import { Controller } from "@hotwired/stimulus"

// Drives the expense/revenue account checkboxes on the accounts index. Selecting two or more
// accounts of the same kind and currency reveals a Merge action; the user then picks which
// account to keep before confirming. Mirrors transactions--selection, minus the merge-pair
// and exclude/restore logic.
export default class extends Controller {
  static targets = [ "checkbox", "bar", "count", "message", "mergeButton", "confirmation", "targetList", "targetTemplate" ]

  connect() {
    // The browser restores checkbox state across a reload, so seed the selection from whatever
    // is already checked and reflect it in the action bar — otherwise the bar stays hidden while
    // boxes appear checked.
    this.selectedIds = this.checkboxTargets.filter(checkbox => checkbox.checked).map(checkbox => checkbox.dataset.accountId)
    this.updateBar()
  }

  toggle(event) {
    const id = event.target.dataset.accountId

    if (event.target.checked) {
      this.selectedIds.push(id)
    } else {
      this.selectedIds = this.selectedIds.filter(selectedId => selectedId !== id)
    }

    this.updateBar()
  }

  updateBar() {
    if (this.selectedIds.length < 1) {
      this.hideBar()
      this.hideConfirmation()
      return
    }

    const noun = this.selectedIds.length === 1 ? "account" : "accounts"
    this.countTarget.textContent = `${this.selectedIds.length} ${noun} selected`

    const validation = this.validateSelection()
    this.mergeButtonTarget.disabled = !validation.valid
    this.messageTarget.textContent = validation.valid ? "" : validation.reason

    this.barTarget.hidden = false
  }

  // Merge requires two or more accounts that all share one kind and one currency.
  validateSelection() {
    if (this.selectedIds.length < 2) {
      return { valid: false, reason: "Select two or more accounts to merge" }
    }

    const rows = this.selectedRows()
    const kinds = new Set(rows.map(row => row.dataset.kind))
    const currencies = new Set(rows.map(row => row.dataset.currencyId))

    if (kinds.size > 1) {
      return { valid: false, reason: "Selected accounts must be the same type" }
    }
    if (currencies.size > 1) {
      return { valid: false, reason: "Selected accounts must use the same currency" }
    }
    return { valid: true }
  }

  selectedRows() {
    return this.selectedIds.map(id => this.checkboxFor(id)).filter(Boolean)
  }

  checkboxFor(id) {
    return this.checkboxTargets.find(checkbox => checkbox.dataset.accountId === id)
  }

  showConfirmation() {
    if (!this.validateSelection().valid) return

    const rows = this.selectedRows()
    // Default to the account with the most transactions, tie-broken by the lowest id (oldest).
    const defaultId = rows
      .slice()
      .sort((a, b) => {
        const byCount = Number(b.dataset.transactionCount) - Number(a.dataset.transactionCount)
        return byCount !== 0 ? byCount : Number(a.dataset.accountId) - Number(b.dataset.accountId)
      })[0].dataset.accountId

    this.targetListTarget.replaceChildren()
    rows.forEach(row => {
      const id = row.dataset.accountId
      const fragment = this.targetTemplateTarget.content.cloneNode(true)

      const radio = fragment.querySelector("input[name='target_account_id']")
      radio.value = id
      radio.checked = id === defaultId

      fragment.querySelector(".selection-confirmation__target-name").textContent = row.dataset.accountName

      const count = Number(row.dataset.transactionCount)
      fragment.querySelector(".selection-confirmation__target-count").textContent =
        `${count} ${count === 1 ? "transaction" : "transactions"}`

      fragment.querySelector("input[name='account_ids[]']").value = id

      this.targetListTarget.appendChild(fragment)
    })

    const noun = rows.length === 1 ? "account" : "accounts"
    this.confirmationTarget.querySelector(".selection-confirmation__preview").textContent =
      `${rows.length} ${noun} will be merged into the one you keep.`

    this.confirmationTarget.hidden = false
    this.barTarget.hidden = true
  }

  hideBar() {
    this.barTarget.hidden = true
  }

  hideConfirmation() {
    this.confirmationTarget.hidden = true
  }

  cancel() {
    this.selectedIds = []
    this.checkboxTargets.forEach(checkbox => { checkbox.checked = false })
    this.hideBar()
    this.hideConfirmation()
  }
}
