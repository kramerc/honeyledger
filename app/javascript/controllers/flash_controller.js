import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    setTimeout(() => this.dismiss(), 4000)
  }

  dismiss() {
    this.element.style.transition = "opacity 0.4s ease, max-height 0.4s ease, padding 0.4s ease, margin 0.4s ease"
    this.element.style.opacity = "0"
    this.element.style.maxHeight = "0"
    this.element.style.paddingTop = "0"
    this.element.style.paddingBottom = "0"
    this.element.style.marginBottom = "0"
    this.element.style.overflow = "hidden"
    setTimeout(() => this.element.remove(), 450)
  }
}
