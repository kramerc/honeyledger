import { Controller } from "@hotwired/stimulus"

// Native HTML5 drag-and-drop to reorder rules (position = priority, first row wins).
// Reorders the DOM optimistically, then POSTs the new id order; the server reassigns
// priority and returns 204. No drag library needed.
export default class extends Controller {
  static targets = ["row"]
  static values = { url: String }

  dragStart(event) {
    this.draggedId = event.currentTarget.dataset.ruleId
    event.currentTarget.classList.add("ir-rule--dragging")
    event.dataTransfer.effectAllowed = "move"
    try { event.dataTransfer.setData("text/plain", this.draggedId) } catch (_) { /* some browsers */ }
  }

  dragOver(event) {
    event.preventDefault()
    const over = event.currentTarget
    if (this.draggedId && over.dataset.ruleId !== this.draggedId) {
      over.classList.add("ir-rule--dragover")
    }
  }

  dragLeave(event) {
    event.currentTarget.classList.remove("ir-rule--dragover")
  }

  drop(event) {
    event.preventDefault()
    const over = event.currentTarget
    over.classList.remove("ir-rule--dragover")

    const dragged = this.rowTargets.find(row => row.dataset.ruleId === this.draggedId)
    if (!dragged || dragged === over) return

    const draggedIndex = this.rowTargets.indexOf(dragged)
    const overIndex = this.rowTargets.indexOf(over)
    if (draggedIndex < overIndex) {
      over.after(dragged)
    } else {
      over.before(dragged)
    }

    this.persist()
  }

  dragEnd() {
    this.rowTargets.forEach(row => row.classList.remove("ir-rule--dragging", "ir-rule--dragover"))
    this.draggedId = null
  }

  persist() {
    const ids = this.rowTargets.map(row => row.dataset.ruleId)
    const token = document.querySelector('meta[name="csrf-token"]')?.content

    fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": token
      },
      body: JSON.stringify({ ids })
    }).then(response => {
      if (!response.ok) window.location.reload()
    }).catch(() => window.location.reload())
  }
}
