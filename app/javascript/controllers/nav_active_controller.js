import { Controller } from "@hotwired/stimulus"

// Reapplies the `active` class to nav links whose `data-nav-active-path` matches
// the current URL. Needed because Turbo Stream broadcasts re-render sidebar items
// without a request context, so server-side `request.path` matching is unavailable.
export default class extends Controller {
  connect() {
    this.update()
    this.observer = new MutationObserver(() => this.update())
    this.observer.observe(this.element, { childList: true, subtree: true })
    this.boundUpdate = () => this.update()
    document.addEventListener("turbo:load", this.boundUpdate)
  }

  disconnect() {
    this.observer?.disconnect()
    document.removeEventListener("turbo:load", this.boundUpdate)
  }

  update() {
    const path = window.location.pathname
    this.element.querySelectorAll("[data-nav-active-path]").forEach((link) => {
      const target = link.dataset.navActivePath
      const active = path === target || path.startsWith(`${target}/`)
      link.classList.toggle("active", active)
    })
  }
}
