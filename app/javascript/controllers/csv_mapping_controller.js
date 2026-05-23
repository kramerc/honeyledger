import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["radio", "signed", "debitCredit", "signIndicator"]
  static values = { mode: String }

  connect() {
    this.update()
  }

  change() {
    const checked = this.radioTargets.find(radio => radio.checked)
    if (checked) {
      this.modeValue = checked.value
    }
    this.update()
  }

  update() {
    const mode = this.modeValue || "signed"
    if (this.hasSignedTarget) this.signedTarget.hidden = mode !== "signed"
    if (this.hasDebitCreditTarget) this.debitCreditTarget.hidden = mode !== "debit_credit"
    if (this.hasSignIndicatorTarget) this.signIndicatorTarget.hidden = mode !== "sign_indicator"
  }
}
