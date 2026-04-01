import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "form", "mergedDetails" ]

  edit(event) {
    event.preventDefault()
    this.element.classList.add("editing")
  }

  cancelEdit(event) {
    event.preventDefault()
    this.closeEdit()
    this.formTarget.reset()
  }

  closeEdit() {
    this.element.classList.remove("editing")
  }

  toggleMergedDetails(event) {
    event.preventDefault()
    if (!this.hasMergedDetailsTarget) return
    this.mergedDetailsTarget.classList.toggle("merged-details--visible")
  }
}
