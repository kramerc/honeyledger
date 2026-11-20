import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "form", "mergedDetails" ]

  edit(event) {
    event.preventDefault()
    this.element.classList.add("editing")
  }

  // Clicking a cell enters edit mode with that cell's field focused; Save
  // confirms and Cancel (or Escape) discards, as with the Edit link.
  editField(event) {
    event.preventDefault()
    this.element.classList.add("editing")

    const name = event.currentTarget.dataset.field
    const field = this.findEditField(name)
    if (field) {
      this.focusField(field)
    } else {
      // The edit form is a lazy frame; focus once it has loaded.
      this.editFrame?.addEventListener("turbo:frame-load", () => {
        const loaded = this.findEditField(name)
        if (loaded) this.focusField(loaded)
      }, { once: true })
    }
  }

  // Hovering a cell starts loading the edit form so it's there by the click.
  preloadEdit() {
    const frame = this.editFrame
    if (frame && frame.getAttribute("loading") === "lazy") frame.setAttribute("loading", "eager")
  }

  get editFrame() {
    return this.element.querySelector("turbo-frame.edit")
  }

  findEditField(name) {
    return this.editFrame?.querySelector(`[name="${CSS.escape(name)}"]:not([type="hidden"])`)
  }

  focusField(field) {
    field.focus()
    if (field.tagName === "SELECT") {
      try { field.showPicker() } catch { /* needs a recent user gesture; focus is enough */ }
    } else if (field.type === "text") {
      field.select()
    }
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
