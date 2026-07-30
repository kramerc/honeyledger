import { Controller } from "@hotwired/stimulus"

// Opens a native <dialog> and lazily loads content into its Turbo Frame. Used for the
// per-rule Preview and the Preview & apply-all modals. Sets the frame src imperatively
// (don't rely on lazy loading inside a hidden dialog), clears it on close so re-opening
// re-fetches fresh, and closes on Turbo cache / backdrop click / successful submit.
export default class extends Controller {
  static targets = ["dialog", "frame"]

  connect() {
    this.closeOnCache = this.closeOnCache.bind(this)
    document.addEventListener("turbo:before-cache", this.closeOnCache)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.closeOnCache)
  }

  open(event) {
    event.preventDefault()
    const src = event.params.src
    if (src) this.frameTarget.src = src
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
  }

  close() {
    if (this.dialogTarget.open) this.dialogTarget.close()
    this.frameTarget.removeAttribute("src")
    this.frameTarget.innerHTML = ""
  }

  // Close when the dialog itself (the backdrop) is clicked, not its content.
  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  // Close after the in-modal "Apply" submits successfully.
  submitEnd(event) {
    if (event.detail.success) this.close()
  }

  // "Apply" in the per-rule preview: persist the rule via the editor form (create/update),
  // flagged to also apply retroactively — so the user's edits are saved, not discarded.
  applyAndSave(event) {
    event.preventDefault()
    const form = document.querySelector("#rule_editor form")
    if (!form) return

    let flag = form.querySelector("input[name='apply_after_save']")
    if (!flag) {
      flag = document.createElement("input")
      flag.type = "hidden"
      flag.name = "apply_after_save"
      form.appendChild(flag)
    }
    flag.value = "1"

    this.close()
    form.requestSubmit()
  }

  closeOnCache() {
    if (this.dialogTarget.open) this.close()
  }
}
