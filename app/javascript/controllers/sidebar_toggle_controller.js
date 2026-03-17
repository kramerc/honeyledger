import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sidebar", "overlay", "button"]

  toggle() {
    const open = this.sidebarTarget.classList.toggle("sidebar--open")
    this.overlayTarget.classList.toggle("sidebar-overlay--visible")
    if (this.hasButtonTarget) this.buttonTarget.setAttribute("aria-expanded", open)
  }

  close() {
    this.sidebarTarget.classList.remove("sidebar--open")
    this.overlayTarget.classList.remove("sidebar-overlay--visible")
    if (this.hasButtonTarget) this.buttonTarget.setAttribute("aria-expanded", "false")
  }
}
