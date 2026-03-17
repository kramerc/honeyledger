import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.isDismissing = false
    this.dismissTimeoutId = setTimeout(() => this.dismiss(), 4000)
  }

  disconnect() {
    if (this.dismissTimeoutId) {
      clearTimeout(this.dismissTimeoutId)
      this.dismissTimeoutId = null
    }

    if (this.removeTimeoutId) {
      clearTimeout(this.removeTimeoutId)
      this.removeTimeoutId = null
    }
  }

  dismiss() {
    if (this.isDismissing) return
    this.isDismissing = true

    if (this.dismissTimeoutId) {
      clearTimeout(this.dismissTimeoutId)
      this.dismissTimeoutId = null
    }

    this.element.style.transition = "opacity 0.4s ease, max-height 0.4s ease, padding 0.4s ease, margin 0.4s ease"
    this.element.style.opacity = "0"
    this.element.style.maxHeight = "0"
    this.element.style.paddingTop = "0"
    this.element.style.paddingBottom = "0"
    this.element.style.marginBottom = "0"
    this.element.style.overflow = "hidden"

    this.removeTimeoutId = setTimeout(() => {
      this.element.remove()
      this.removeTimeoutId = null
    }, 450)
  }
}
