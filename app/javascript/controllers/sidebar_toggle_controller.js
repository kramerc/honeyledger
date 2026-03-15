import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sidebar", "overlay"]

  toggle() {
    this.sidebarTarget.classList.toggle("sidebar--open")
    this.overlayTarget.classList.toggle("sidebar-overlay--visible")
  }

  close() {
    this.sidebarTarget.classList.remove("sidebar--open")
    this.overlayTarget.classList.remove("sidebar-overlay--visible")
  }
}
