import { Controller } from "@hotwired/stimulus"

// Shows and hides a region by toggling a class on the controller element, so
// the open state survives Turbo replacing the region's contents.
export default class extends Controller {
  static targets = [ "button" ]
  static classes = [ "open" ]

  toggle() {
    const open = this.element.classList.toggle(this.openClass)
    if (this.hasButtonTarget) this.buttonTarget.setAttribute("aria-expanded", String(open))
  }
}
