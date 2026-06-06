import { Controller } from "@hotwired/stimulus"

// Drives the transaction-row checkboxes. Any number of rows can be selected to
// run bulk actions (delete, exclude, restore); when exactly two selected rows
// form a valid transfer pair, the merge action is also offered.
export default class extends Controller {
  static targets = [
    "checkbox", "bar", "count",
    "deleteButton", "excludeButton", "restoreButton", "mergeButton", "mergeMessage",
    "combineButton", "combineConfirmation", "combineOptions", "combineForm", "combineSurvivorId",
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
      this.hideCombineConfirmation()
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
    this.updateCombineButton()

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

  updateCombineButton() {
    if (!this.hasCombineButtonTarget) return

    const anyExcluded = this.selectedRows().some(row => row.dataset.selectionExcluded === "true")

    if (this.selectedIds.length < 2 || anyExcluded) {
      this.combineButtonTarget.disabled = true
      return
    }

    const rows = this.selectedIds.map(id => this.transactionData(id))
    this.combineButtonTarget.disabled = !rows.every(Boolean) || !this.validateDuplicates(rows)
  }

  // Duplicates of one event: equal amount + currency, each a non-transfer, all
  // sharing the same bank account on the same side (all src == BankX, or all
  // dest == BankX). Mutually exclusive with a valid transfer pair.
  validateDuplicates(rows) {
    const balanceSheetKinds = this.constructor.BALANCE_SHEET_KINDS
    const isBs = kind => balanceSheetKinds.includes(kind)

    if (new Set(rows.map(r => r.amountMinor)).size !== 1) return false
    if (new Set(rows.map(r => r.currencyCode)).size !== 1) return false

    // FX and split rows are rejected by Transaction::Deduplicate, so don't offer
    // the action for them — mirror those server guards here.
    if (rows.some(r => r.hasFx || r.isSplit)) return false

    // Each must be a non-transfer: exactly one balance-sheet side.
    if (!rows.every(r => isBs(r.srcKind) !== isBs(r.destKind))) return false

    const allSrc = rows.every(r => isBs(r.srcKind))
    const allDest = rows.every(r => isBs(r.destKind))

    if (allSrc) return new Set(rows.map(r => r.srcAccountId)).size === 1
    if (allDest) return new Set(rows.map(r => r.destAccountId)).size === 1
    return false
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
      category: row.dataset.mergeCategory,
      hasFx: row.dataset.mergeHasFx === "true",
      isSplit: row.dataset.mergeSplit === "true",
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

  // --- Combine duplicates confirmation --------------------------------------

  showCombineConfirmation() {
    if (!this.hasCombineConfirmationTarget) return

    const rows = this.selectedIds.map(id => this.transactionData(id)).filter(Boolean)
    if (rows.length < 2 || !this.validateDuplicates(rows)) return

    const defaultId = this.defaultSurvivorId(rows)

    this.combineOptionsTarget.innerHTML = ""
    rows.forEach(row => {
      const label = document.createElement("label")
      label.className = "selection-confirmation__option"

      const input = document.createElement("input")
      input.type = "radio"
      input.name = "combine_survivor"
      input.value = row.id
      input.checked = row.id === defaultId

      const body = document.createElement("span")
      body.className = "selection-confirmation__option-body"

      const title = document.createElement("span")
      title.className = "selection-confirmation__option-title"
      title.textContent = row.description || "(no description)"

      // Lead the subtext with the date — the field that distinguishes otherwise
      // identical duplicates.
      const details = []
      if (row.transactedAt) details.push(row.transactedAt.replace("T", " "))
      details.push(`${row.srcAccountName} → ${row.destAccountName}`)
      if (row.category) details.push(row.category)

      const detail = document.createElement("span")
      detail.className = "selection-confirmation__option-detail"
      detail.textContent = details.join(" · ")

      body.appendChild(title)
      body.appendChild(detail)
      label.appendChild(input)
      label.appendChild(body)
      this.combineOptionsTarget.appendChild(label)
    })

    this.combineConfirmationTarget.hidden = false
    this.barTarget.hidden = true
  }

  // Heuristic default (mirrors Transaction::Deduplicate): a categorized row,
  // else the oldest by transacted_at. When transacted_at ties — common for
  // duplicates — break by smallest id (the older record) so the default is
  // stable rather than dependent on selection order.
  defaultSurvivorId(rows) {
    const categorized = rows.filter(row => row.category && row.category.length > 0)
    const pool = categorized.length > 0 ? categorized : rows
    return pool.reduce((best, row) => {
      if (row.transactedAt < best.transactedAt) return row
      if (row.transactedAt === best.transactedAt && Number(row.id) < Number(best.id)) return row
      return best
    }).id
  }

  submitCombine() {
    const checked = this.combineOptionsTarget.querySelector("input[name='combine_survivor']:checked")
    if (!checked) return
    this.combineSurvivorIdTarget.value = checked.value
    this.submitBulk(this.combineFormTarget)
  }

  hideCombineConfirmation() {
    if (!this.hasCombineConfirmationTarget) return
    this.combineConfirmationTarget.hidden = true
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
    this.hideCombineConfirmation()
    this.hideDeleteConfirmation()
  }

  formatAmount(minorStr, decimalPlaces) {
    const minor = parseInt(minorStr, 10)
    const divisor = Math.pow(10, decimalPlaces)
    return (minor / divisor).toFixed(decimalPlaces)
  }
}
