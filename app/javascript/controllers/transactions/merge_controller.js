import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "mergeBar", "mergeButton", "mergeMessage", "confirmation"]
  static values = {
    mergeUrl: String
  }

  static BALANCE_SHEET_KINDS = ["asset", "liability", "equity"]

  connect() {
    this.selectedIds = []
  }

  toggle(event) {
    const checkbox = event.target
    const id = checkbox.dataset.transactionId

    if (checkbox.checked) {
      // Limit to 2 selections: uncheck the oldest if already at 2
      if (this.selectedIds.length >= 2) {
        const oldestId = this.selectedIds.shift()
        const oldCheckbox = this.checkboxTargets.find(cb => cb.dataset.transactionId === oldestId)
        if (oldCheckbox) oldCheckbox.checked = false
      }
      this.selectedIds.push(id)
    } else {
      this.selectedIds = this.selectedIds.filter(sid => sid !== id)
    }

    this.updateMergeBar()
  }

  updateMergeBar() {
    if (this.selectedIds.length < 2) {
      this.hideMergeBar()
      this.hideConfirmation()
      return
    }

    const [dataA, dataB] = this.selectedIds.map(id => this.transactionData(id))
    if (!dataA || !dataB) {
      this.hideMergeBar()
      return
    }

    const validation = this.validatePair(dataA, dataB)
    this.showMergeBar(validation)
  }

  transactionData(id) {
    const checkbox = this.checkboxTargets.find(cb => cb.dataset.transactionId === id)
    if (!checkbox) return null

    const row = checkbox.closest("[data-merge-amount-minor]")
    if (!row) return null

    return {
      id,
      amountMinor: row.dataset.mergeAmountMinor,
      srcKind: row.dataset.mergeSrcKind,
      destKind: row.dataset.mergeDestKind,
      srcAccountName: row.dataset.mergeSrcAccountName,
      destAccountName: row.dataset.mergeDestAccountName,
      description: row.dataset.mergeDescription,
      transactedAt: row.dataset.mergeTransactedAt,
      currencyCode: row.dataset.mergeCurrencyCode
    }
  }

  validatePair(a, b) {
    const bs = this.constructor.BALANCE_SHEET_KINDS

    if (a.amountMinor !== b.amountMinor) {
      return { valid: false, reason: "Amounts must match" }
    }

    const aSrcBs = bs.includes(a.srcKind)
    const bSrcBs = bs.includes(b.srcKind)
    const aDestBs = bs.includes(a.destKind)
    const bDestBs = bs.includes(b.destKind)

    if (aSrcBs && bDestBs) {
      return { valid: true, srcName: a.srcAccountName, destName: b.destAccountName }
    } else if (bSrcBs && aDestBs) {
      return { valid: true, srcName: b.srcAccountName, destName: a.destAccountName }
    } else {
      return { valid: false, reason: "One transaction must have a bank account as the source and the other as the destination" }
    }
  }

  showMergeBar(validation) {
    if (!this.hasMergeBarTarget) return

    this.mergeBarTarget.hidden = false

    if (validation.valid) {
      this.mergeButtonTarget.disabled = false
      this.mergeMessageTarget.textContent = `${validation.srcName} \u2192 ${validation.destName}`
    } else {
      this.mergeButtonTarget.disabled = true
      this.mergeMessageTarget.textContent = validation.reason
    }
  }

  hideMergeBar() {
    if (!this.hasMergeBarTarget) return
    this.mergeBarTarget.hidden = true
  }

  showConfirmation() {
    if (!this.hasConfirmationTarget) return

    const [dataA, dataB] = this.selectedIds.map(id => this.transactionData(id))
    if (!dataA || !dataB) return

    const validation = this.validatePair(dataA, dataB)
    if (!validation.valid) return

    // Populate confirmation fields
    const form = this.confirmationTarget.querySelector("form")
    form.querySelector("[name='transaction_ids[]'][data-slot='a']").value = this.selectedIds[0]
    form.querySelector("[name='transaction_ids[]'][data-slot='b']").value = this.selectedIds[1]

    const descInput = form.querySelector("[name='description']")
    descInput.value = dataA.description || dataB.description || ""

    const dateInput = form.querySelector("[name='transacted_at']")
    // Use the earlier date
    const dateA = dataA.transactedAt
    const dateB = dataB.transactedAt
    dateInput.value = (dateA && dateB) ? (dateA < dateB ? dateA : dateB) : (dateA || dateB || "")

    const preview = this.confirmationTarget.querySelector(".merge-confirmation__preview")
    preview.textContent = `${validation.srcName} \u2192 ${validation.destName} \u00b7 ${dataA.currencyCode} ${this.formatAmount(dataA.amountMinor, dataA.currencyCode)}`

    this.confirmationTarget.hidden = false
    this.mergeBarTarget.hidden = true
  }

  hideConfirmation() {
    if (!this.hasConfirmationTarget) return
    this.confirmationTarget.hidden = true
  }

  cancel() {
    this.selectedIds = []
    this.checkboxTargets.forEach(cb => cb.checked = false)
    this.hideMergeBar()
    this.hideConfirmation()
  }

  formatAmount(minorStr) {
    const minor = parseInt(minorStr, 10)
    // Simple cents-to-dollars formatting (assumes 2 decimal places)
    return (minor / 100).toFixed(2)
  }
}
