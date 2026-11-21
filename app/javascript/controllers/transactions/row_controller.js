import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "form", "mergedDetails" ]

  // Edit (from the row's action menu) hides the menu and its trigger with the
  // rest of the shown row, so focus would fall to the page; land it on the
  // form's first field instead. A tap on a touch screen skips this, so the
  // on-screen keyboard doesn't open over the form uninvited.
  edit(event) {
    event.preventDefault()
    this.startEditing()

    const keyboard = event.detail === 0 // a click synthesised from Enter or Space
    if (keyboard || window.matchMedia("(pointer: fine)").matches) this.focusFirstField()
  }

  focusFirstField() {
    const first = () => this.editFrame?.querySelector("input:not([type=hidden]), select")
    const field = first()
    if (field) {
      field.focus()
    } else {
      // The edit form is a lazy frame; focus once it has loaded.
      this.editFrame?.addEventListener("turbo:frame-load", () => first()?.focus(), { once: true })
    }
  }

  // Clicking a cell enters edit mode with that cell's field focused; Save
  // confirms and Cancel (or Escape) discards, as with the Edit link.
  editField(event) {
    event.preventDefault()
    this.startEditing()

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

  // Resting on a cell starts loading the edit form so it's there by the
  // click. The delay keeps a pointer sweeping across the table from loading
  // a form for every row it crosses.
  static PRELOAD_DELAY_MS = 250

  disconnect() {
    this.cancelPreload()
  }

  schedulePreload() {
    this.cancelPreload()
    this.preloadTimer = setTimeout(() => this.preloadEdit(), this.constructor.PRELOAD_DELAY_MS)
  }

  cancelPreload() {
    clearTimeout(this.preloadTimer)
    this.preloadTimer = null
  }

  preloadEdit() {
    this.preloadTimer = null
    const frame = this.editFrame
    if (frame && frame.getAttribute("loading") === "lazy") frame.setAttribute("loading", "eager")
  }

  // The Cleared toggle saves without edit mode. If the server rejects it,
  // the errors are rendered into the edit form (edit.turbo_stream), so open
  // edit mode to show them rather than failing silently.
  toggleSubmitEnd(event) {
    if (!event.detail.success) this.startEditing()
  }

  // Enter edit mode. The shown row stays on screen until the form has loaded
  // (transactions.css), and a hidden lazy frame would never start loading on
  // its own, so start it here.
  startEditing() {
    this.cancelPreload()
    this.element.classList.add("editing")
    this.preloadEdit()
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
    // Escape on a select whose list is open only closes the list; the next
    // Escape discards the edit. Clicking From, To, or Category opens its list
    // straight away, so this is the common way out of a list. Chrome already
    // keeps that Escape from reaching the page; this guard covers browsers
    // that let it through.
    if (event.type === "keydown" && this.isOpenSelect(event.target)) return

    event.preventDefault()
    this.closeEdit()
    this.formTarget.reset()
  }

  // :open matches a select with its list showing. Browsers without :open
  // support throw on the selector, and Escape keeps discarding there.
  isOpenSelect(element) {
    if (element?.tagName !== "SELECT") return false
    try { return element.matches(":open") } catch { return false }
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
