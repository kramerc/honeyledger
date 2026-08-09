import { Controller } from "@hotwired/stimulus"

// Drives the editor's "Assign to account" / "Exclude" two-button toggle. When excluding,
// hides the account select and clears its value (so the rule saves with no account);
// when switching back to assigning, restores the previously chosen account. Backed by the
// `exclude` radio pair so the choice submits as a real form value.
export default class extends Controller {
  static targets = ["radio", "accountField", "account", "note"]

  connect() {
    this.toggle()
  }

  toggle() {
    const excluded = this.radioTargets.some(radio => radio.value === "true" && radio.checked)

    if (this.hasAccountFieldTarget) this.accountFieldTarget.hidden = excluded
    if (this.hasNoteTarget) this.noteTarget.hidden = !excluded

    if (this.hasAccountTarget) {
      if (excluded) {
        // Remember the choice so it can be restored, then clear it (the select stays enabled
        // but hidden, so the empty value submits and the saved rule ends up with no account).
        if (this.accountTarget.value) this.savedAccount = this.accountTarget.value
        this.accountTarget.value = ""
      } else if (this.savedAccount) {
        this.accountTarget.value = this.savedAccount
      }
    }
  }
}
