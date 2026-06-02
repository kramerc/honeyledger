import { Controller } from "@hotwired/stimulus"

// Drives the expense/revenue account checkboxes on the accounts index. Selecting two or more
// accounts of the same kind and currency reveals a Merge action; the user then picks which
// account to keep before confirming. Mirrors transactions--selection, minus the merge-pair
// and exclude/restore logic.
export default class extends Controller {
  static targets = [ "checkbox", "bar", "count", "message", "mergeButton", "confirmation", "targetList" ]

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

    const form = this.confirmationTarget.querySelector("form")
    form.querySelectorAll("input[name='account_ids[]']").forEach(input => input.remove())
    this.targetListTarget.innerHTML = ""

    rows.forEach(row => {
      const id = row.dataset.accountId

      const label = document.createElement("label")
      label.className = "selection-confirmation__target"

      const radio = document.createElement("input")
      radio.type = "radio"
      radio.name = "target_account_id"
      radio.value = id
      radio.checked = id === defaultId
      label.appendChild(radio)

      const name = document.createElement("span")
      name.className = "selection-confirmation__target-name"
      name.textContent = row.dataset.accountName
      label.appendChild(name)

      const count = Number(row.dataset.transactionCount)
      const meta = document.createElement("span")
      meta.className = "selection-confirmation__target-count"
      meta.textContent = `${count} ${count === 1 ? "transaction" : "transactions"}`
      label.appendChild(meta)

      this.targetListTarget.appendChild(label)

      const hidden = document.createElement("input")
      hidden.type = "hidden"
      hidden.name = "account_ids[]"
      hidden.value = id
      form.appendChild(hidden)
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
