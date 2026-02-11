import { Controller } from "@hotwired/stimulus"

// Toggles between a <select> (existing categories) and a text input (new category).
// When the select's value is "__new__", the text input is shown.
// Targets:
//   select   – the <select> element
//   textInput – the text <input> for new category
//   nameField – hidden input that carries the submitted value
export default class extends Controller {
  static targets = ["select", "textInput", "nameField", "newWrapper"]

  connect() {
    this.syncVisibility()
  }

  changed() {
    this.syncVisibility()
  }

  // Switch back to the select dropdown
  back(event) {
    event.preventDefault()
    this.selectTarget.value = ""
    this.textInputTarget.value = ""
    this.syncVisibility()
  }

  syncVisibility() {
    const isNew = this.selectTarget.value === "__new__"

    this.selectTarget.style.display = isNew ? "none" : ""
    if (this.hasNewWrapperTarget) {
      this.newWrapperTarget.style.display = isNew ? "" : "none"
    }

    if (isNew) {
      this.nameFieldTarget.value = this.textInputTarget.value
      this.textInputTarget.focus()
    } else {
      // Write the selected option's text as category_name
      const selected = this.selectTarget.options[this.selectTarget.selectedIndex]
      this.nameFieldTarget.value = selected && selected.value !== "" ? selected.text : ""
    }
  }

  typed() {
    this.nameFieldTarget.value = this.textInputTarget.value
  }
}
