import { Controller } from "@hotwired/stimulus"

// Toggles between a <select> (existing categories) and a text input (new category).
// When the select's value is "__new__", the text input is shown.
// For existing categories, sets category_id. For new categories, sets category_name.
// Targets:
//   select    – the <select> element
//   textInput – the text <input> for new category
//   idField   – hidden input for category_id (existing categories)
//   nameField – hidden input for category_name (new categories only)
export default class extends Controller {
  static targets = ["select", "textInput", "idField", "nameField", "newWrapper"]

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
      // Creating a new category: clear ID, set name from text input
      this.idFieldTarget.value = ""
      this.nameFieldTarget.value = this.textInputTarget.value
      this.textInputTarget.focus()
    } else {
      // Using existing category: set ID from select value, clear name
      this.idFieldTarget.value = this.selectTarget.value
      this.nameFieldTarget.value = ""
    }
  }

  typed() {
    // When typing a new category name, keep ID empty and update name
    this.idFieldTarget.value = ""
    this.nameFieldTarget.value = this.textInputTarget.value
  }
}
