import { Controller } from "@hotwired/stimulus"

// Dynamically updates the transaction type indicator based on selected
// From (src) and To (dest) accounts. Each <option> carries a data-kind
// attribute (asset, liability, equity, expense, revenue).
export default class extends Controller {
  static targets = ["src", "dest", "indicator", "currency"]

  connect() {
    this.update()
  }

  update() {
    if (!this.hasSrcTarget || !this.hasDestTarget || !this.hasIndicatorTarget) return

    const srcKind = this.selectedKind(this.srcTarget)
    const destKind = this.selectedKind(this.destTarget)

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

    this.indicatorTarget.textContent = label
    this.indicatorTarget.style.color = color

    if (this.hasCurrencyTarget) {
      const destOption = this.destTarget.options[this.destTarget.selectedIndex]
      this.currencyTarget.textContent = destOption ? destOption.dataset.currency || "" : ""
    }
  }

  selectedKind(select) {
    const option = select.options[select.selectedIndex]
    return option ? option.dataset.kind || "" : ""
  }
}
