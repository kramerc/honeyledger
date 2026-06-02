import { Controller } from "@hotwired/stimulus"

// Drives the transaction-row checkboxes. Any number of rows can be selected to
// run bulk actions (delete, exclude, restore); when exactly two selected rows
// form a valid transfer pair, the merge action is also offered.
export default class extends Controller {
  static targets = [
    "checkbox", "bar", "count",
    "deleteButton", "excludeButton", "restoreButton", "mergeButton", "mergeMessage",
    "confirmation", "deleteConfirmation",
    "deleteForm", "excludeForm", "restoreForm"
  ]

  static BALANCE_SHEET_KINDS = [ "asset", "liability", "equity" ]

  connect() {
    // The browser restores checkbox state across a reload, so seed the selection from whatever
    // is already checked and reflect it in the action bar — otherwise the bar stays hidden while
    // boxes appear checked.
    this.selectedIds = this.checkboxTargets.filter(checkbox => checkbox.checked).map(checkbox => checkbox.dataset.transactionId)
    this.updateBar()
  }

  toggle(event) {
    const checkbox = event.target
    const id = checkbox.dataset.transactionId

    if (checkbox.checked) {
      this.selectedIds.push(id)
    } else {
      this.selectedIds = this.selectedIds.filter(sid => sid !== id)
    }

    this.updateBar()
  }

  updateBar() {
    if (this.selectedIds.length < 1) {
      this.hideBar()
      this.hideConfirmation()
      this.hideDeleteConfirmation()
      return
    }

    if (this.hasCountTarget) {
      const noun = this.selectedIds.length === 1 ? "transaction" : "transactions"
      this.countTarget.textContent = `${this.selectedIds.length} ${noun} selected`
    }

    this.updateDeleteButton()
    this.updateExcludeButton()
    this.updateRestoreButton()
    this.updateMergeButton()

    this.barTarget.hidden = false
  }

  updateDeleteButton() {
    if (!this.hasDeleteButtonTarget) return
    // Anything selectable can be deleted.
    this.deleteButtonTarget.disabled = this.selectedIds.length < 1
  }

  updateExcludeButton() {
    if (!this.hasExcludeButtonTarget) return
    const allExcludable = this.selectedRows().every(row => row.dataset.selectionExcludable === "true")
    this.excludeButtonTarget.disabled = !allExcludable
  }

  updateRestoreButton() {
    if (!this.hasRestoreButtonTarget) return
    const allExcluded = this.selectedRows().every(row => row.dataset.selectionExcluded === "true")
    this.restoreButtonTarget.disabled = !allExcluded
  }

  updateMergeButton() {
    if (!this.hasMergeButtonTarget) return

    // Excluded rows are selectable (for Restore) but can never be merged.
    const anyExcluded = this.selectedRows().some(row => row.dataset.selectionExcluded === "true")

    if (this.selectedIds.length !== 2 || anyExcluded) {
      this.mergeButtonTarget.disabled = true
      if (this.hasMergeMessageTarget) this.mergeMessageTarget.textContent = ""
      return
    }

    const [dataA, dataB] = this.selectedIds.map(id => this.transactionData(id))
    if (!dataA || !dataB) {
      this.mergeButtonTarget.disabled = true
      return
    }

    const validation = this.validatePair(dataA, dataB)
    this.mergeButtonTarget.disabled = !validation.valid
    if (this.hasMergeMessageTarget) {
      this.mergeMessageTarget.textContent = validation.valid
        ? `${validation.srcName} → ${validation.destName}`
        : ""
    }
  }

  // --- Row data helpers -----------------------------------------------------

  selectedRows() {
    return this.selectedIds.map(id => this.rowFor(id)).filter(Boolean)
  }

  rowFor(id) {
    const checkbox = this.checkboxTargets.find(cb => cb.dataset.transactionId === id)
    if (!checkbox) return null
    return checkbox.closest("[data-merge-amount-minor]")
  }

  transactionData(id) {
    const row = this.rowFor(id)
    if (!row) return null

    return {
      id,
      amountMinor: row.dataset.mergeAmountMinor,
      srcAccountId: row.dataset.mergeSrcAccountId,
      destAccountId: row.dataset.mergeDestAccountId,
      srcKind: row.dataset.mergeSrcKind,
      destKind: row.dataset.mergeDestKind,
      srcAccountName: row.dataset.mergeSrcAccountName,
      destAccountName: row.dataset.mergeDestAccountName,
      description: row.dataset.mergeDescription,
      transactedAt: row.dataset.mergeTransactedAt,
      currencyCode: row.dataset.mergeCurrencyCode,
      currencyDecimalPlaces: parseInt(row.dataset.mergeCurrencyDecimalPlaces, 10) || 2
    }
  }

  validatePair(a, b) {
    const balanceSheetKinds = this.constructor.BALANCE_SHEET_KINDS
    const incomeExpenseKinds = [ "expense", "revenue" ]

    if (a.amountMinor !== b.amountMinor) {
      return { valid: false, reason: "Amounts must match" }
    }

    const aSrcBs = balanceSheetKinds.includes(a.srcKind)
    const bSrcBs = balanceSheetKinds.includes(b.srcKind)
    const aDestBs = balanceSheetKinds.includes(a.destKind)
    const bDestBs = balanceSheetKinds.includes(b.destKind)

    // Reject transactions that are already transfers (both sides balance-sheet)
    if ((aSrcBs && aDestBs) || (bSrcBs && bDestBs)) {
      return { valid: false, reason: "Cannot merge transactions that are already transfers" }
    }

    // Each must have exactly one balance-sheet side paired with income/expense
    const aValid = (aSrcBs && incomeExpenseKinds.includes(a.destKind)) || (aDestBs && incomeExpenseKinds.includes(a.srcKind))
    const bValid = (bSrcBs && incomeExpenseKinds.includes(b.destKind)) || (bDestBs && incomeExpenseKinds.includes(b.srcKind))

    if (!aValid || !bValid) {
      return { valid: false, reason: "Each transaction must be between a bank account and an income/expense account" }
    }

    // One must be BS→IE (withdrawal), the other IE→BS (deposit)
    if (aSrcBs && bDestBs) {
      if (a.srcAccountId === b.destAccountId) {
        return { valid: false, reason: "Source and destination accounts cannot be the same" }
      }
      return { valid: true, srcName: a.srcAccountName, destName: b.destAccountName }
    } else if (bSrcBs && aDestBs) {
      if (b.srcAccountId === a.destAccountId) {
        return { valid: false, reason: "Source and destination accounts cannot be the same" }
      }
      return { valid: true, srcName: b.srcAccountName, destName: a.destAccountName }
    } else {
      return { valid: false, reason: "One transaction must be a withdrawal and the other a deposit" }
    }
  }

  // --- Bulk actions ---------------------------------------------------------

  submitExclude() {
    this.submitBulk(this.excludeFormTarget)
  }

  submitRestore() {
    this.submitBulk(this.restoreFormTarget)
  }

  confirmDelete() {
    if (!this.hasDeleteConfirmationTarget) return
    const preview = this.deleteConfirmationTarget.querySelector(".selection-confirmation__preview")
    if (preview) {
      const noun = this.selectedIds.length === 1 ? "transaction" : "transactions"
      preview.textContent = `${this.selectedIds.length} ${noun} will be permanently deleted.`
    }
    this.deleteConfirmationTarget.hidden = false
    this.barTarget.hidden = true
  }

  submitDelete() {
    this.submitBulk(this.deleteFormTarget)
  }

  // Dismiss the delete confirmation without clearing the selection — the user
  // is undoing the "Delete" click, not the selection itself.
  cancelDelete() {
    this.hideDeleteConfirmation()
    this.updateBar()
  }

  // Injects the current selection as transaction_ids[] hidden inputs into the
  // given form, then submits it. Turbo handles the streamed response.
  submitBulk(form) {
    form.querySelectorAll("input[name='transaction_ids[]']").forEach(input => input.remove())
    this.selectedIds.forEach(id => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "transaction_ids[]"
      input.value = id
      form.appendChild(input)
    })
    form.requestSubmit()
  }

  // --- Merge confirmation ---------------------------------------------------

  showConfirmation() {
    if (!this.hasConfirmationTarget) return

    const [dataA, dataB] = this.selectedIds.map(id => this.transactionData(id))
    if (!dataA || !dataB) return

    const validation = this.validatePair(dataA, dataB)
    if (!validation.valid) return

    const form = this.confirmationTarget.querySelector("form")
    form.querySelector("[name='transaction_ids[]'][data-slot='a']").value = this.selectedIds[0]
    form.querySelector("[name='transaction_ids[]'][data-slot='b']").value = this.selectedIds[1]

    const descInput = form.querySelector("[name='description']")
    descInput.value = dataA.description || dataB.description || ""

    const dateInput = form.querySelector("[name='transacted_at']")
    const dateA = dataA.transactedAt
    const dateB = dataB.transactedAt
    dateInput.value = (dateA && dateB) ? (dateA < dateB ? dateA : dateB) : (dateA || dateB || "")

    const preview = this.confirmationTarget.querySelector(".selection-confirmation__preview")
    preview.textContent = `${validation.srcName} → ${validation.destName} · ${dataA.currencyCode} ${this.formatAmount(dataA.amountMinor, dataA.currencyDecimalPlaces)}`

    this.confirmationTarget.hidden = false
    this.barTarget.hidden = true
  }

  hideConfirmation() {
    if (!this.hasConfirmationTarget) return
    this.confirmationTarget.hidden = true
  }

  hideDeleteConfirmation() {
    if (!this.hasDeleteConfirmationTarget) return
    this.deleteConfirmationTarget.hidden = true
  }

  hideBar() {
    if (!this.hasBarTarget) return
    this.barTarget.hidden = true
  }

  cancel() {
    this.selectedIds = []
    this.checkboxTargets.forEach(cb => cb.checked = false)
    this.hideBar()
    this.hideConfirmation()
    this.hideDeleteConfirmation()
  }

  formatAmount(minorStr, decimalPlaces) {
    const minor = parseInt(minorStr, 10)
    const divisor = Math.pow(10, decimalPlaces)
    return (minor / divisor).toFixed(decimalPlaces)
  }
}
