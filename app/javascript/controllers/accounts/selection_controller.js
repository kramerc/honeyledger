import { Controller } from "@hotwired/stimulus"

// Drives the expense/revenue account checkboxes on the accounts index. Selecting two or more
// accounts of the same kind and currency reveals a Merge action; the user then picks which
// account to keep before confirming. Empty accounts (no transactions) can also be cleaned up:
// the header "Clean up" button selects every empty account at once, and a bar Delete button
// removes a hand-picked subset — both open the same reviewable confirmation before deleting.
// Mirrors transactions--selection, minus the merge-pair and exclude/restore logic.
export default class extends Controller {
  static targets = [ "checkbox", "bar", "count", "message", "mergeButton", "confirmation",
    "targetList", "targetTemplate", "deleteButton", "cleanupButton", "cleanupForm",
    "cleanupConfirmation", "cleanupList", "cleanupItemTemplate" ]

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
      this.hideCleanupConfirmation()
      return
    }

    const noun = this.selectedIds.length === 1 ? "account" : "accounts"
    this.countTarget.textContent = `${this.selectedIds.length} ${noun} selected`

    const validation = this.validateSelection()
    this.mergeButtonTarget.disabled = !validation.valid
    this.messageTarget.textContent = validation.valid ? "" : validation.reason

    // Delete is offered only when every checked account is empty — the per-row checkbox carries
    // its transaction count, and "0" means it can be destroyed (restrict_with_error otherwise).
    if (this.hasDeleteButtonTarget) {
      this.deleteButtonTarget.hidden = !this.selectedRows().every(row => row.dataset.transactionCount === "0")
    }

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

  // Header "Clean up" affordance: check every empty account the server flagged, then open the
  // reviewable confirmation listing exactly what will be deleted.
  confirmCleanup() {
    const ids = JSON.parse(this.cleanupButtonTarget.dataset.emptyAccountIds || "[]").map(String)
    this.selectedIds = ids
    this.checkboxTargets.forEach(checkbox => { checkbox.checked = ids.includes(checkbox.dataset.accountId) })
    this.openCleanupConfirmation(ids)
  }

  // Bar Delete: confirm the hand-picked subset (only shown when every checked account is empty).
  confirmDeleteSelected() {
    this.openCleanupConfirmation(this.selectedIds)
  }

  openCleanupConfirmation(ids) {
    const rows = ids.map(id => this.checkboxFor(id)).filter(Boolean)

    this.cleanupListTarget.replaceChildren()
    rows.forEach(row => {
      const fragment = this.cleanupItemTemplateTarget.content.cloneNode(true)
      fragment.querySelector(".selection-confirmation__cleanup-name").textContent = row.dataset.accountName
      this.cleanupListTarget.appendChild(fragment)
    })

    const noun = rows.length === 1 ? "account" : "accounts"
    this.cleanupConfirmationTarget.querySelector(".selection-confirmation__preview").textContent =
      `${rows.length} empty expense/revenue ${noun} will be permanently deleted.`

    this.cleanupConfirmationTarget.hidden = false
    this.hideBar()
  }

  submitCleanup() {
    const form = this.cleanupFormTarget
    form.querySelectorAll("input[name='account_ids[]']").forEach(input => input.remove())
    this.selectedIds.forEach(id => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "account_ids[]"
      input.value = id
      form.appendChild(input)
    })
    form.requestSubmit()
  }

  // The header button can be present on a page whose selection bar isn't rendered (the empty
  // accounts state), so guard the bar/confirmation targets here.
  hideBar() {
    if (this.hasBarTarget) this.barTarget.hidden = true
  }

  hideConfirmation() {
    if (this.hasConfirmationTarget) this.confirmationTarget.hidden = true
  }

  hideCleanupConfirmation() {
    if (this.hasCleanupConfirmationTarget) this.cleanupConfirmationTarget.hidden = true
  }

  cancel() {
    this.selectedIds = []
    this.checkboxTargets.forEach(checkbox => { checkbox.checked = false })
    this.hideBar()
    this.hideConfirmation()
    this.hideCleanupConfirmation()
  }
}
