import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "field"]

  connect() {
    this.toggle()
  }

  toggle() {
    this.fieldTarget.disabled = this.checkboxTarget.checked
    if (this.checkboxTarget.checked) {
      this.fieldTarget.value = ''
    }
  }
}
