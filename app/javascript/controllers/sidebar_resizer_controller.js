import { Controller } from "@hotwired/stimulus"

const MIN_SIDEBAR_WIDTH = 100
const MAX_SIDEBAR_WIDTH = 500

export default class extends Controller {
  static targets = ["sidebar"]

  connect() {
    let saved = null

    try {
      saved = localStorage.getItem("sidebarWidth")
    } catch (error) {
      // Ignore storage access issues
    }

    if (saved && !this.isMobile()) {
      const validatedWidth = this.parseSidebarWidth(saved)
      if (validatedWidth) {
        this.setSidebarWidth(validatedWidth)
      }
    }
  }

  disconnect() {
    if (this._onMouseMove) {
      document.removeEventListener("mousemove", this._onMouseMove)
    }
    if (this._onMouseUp) {
      document.removeEventListener("mouseup", this._onMouseUp)
    }
    document.body.style.userSelect = ""
    document.body.style.cursor = ""
  }

  startResize(event) {
    event.preventDefault()
    this._startX = event.clientX
    this._startWidth = this.sidebarTarget.offsetWidth

    this._onMouseMove = this.resize.bind(this)
    this._onMouseUp = this.stopResize.bind(this)

    document.addEventListener("mousemove", this._onMouseMove)
    document.addEventListener("mouseup", this._onMouseUp)
    document.body.style.userSelect = "none"
    document.body.style.cursor = "col-resize"
  }

  resize(event) {
    const width = this._startWidth + (event.clientX - this._startX)
    if (width < MIN_SIDEBAR_WIDTH || width > MAX_SIDEBAR_WIDTH) return

    const widthValue = `${width}px`
    this._currentWidth = widthValue
    this.setSidebarWidth(widthValue)
  }

  stopResize() {
    document.removeEventListener("mousemove", this._onMouseMove)
    document.removeEventListener("mouseup", this._onMouseUp)
    document.body.style.userSelect = ""
    document.body.style.cursor = ""

    if (this.isMobile()) {
      return
    }

    const widthToSave =
      this._currentWidth || `${this.sidebarTarget.offsetWidth}px`

    try {
      localStorage.setItem("sidebarWidth", widthToSave)
    } catch (error) {
      // Ignore storage access issues
    }
  }

  parseSidebarWidth(value) {
    if (typeof value === "string" && /^\d+px$/.test(value)) {
      return value
    }
    return null
  }

  setSidebarWidth(width) {
    const validatedWidth = this.parseSidebarWidth(width)
    if (!validatedWidth) {
      return
    }

    if (this.sidebarTarget && this.sidebarTarget.style) {
      this.sidebarTarget.style.removeProperty("width")
    }
    document.documentElement.style.setProperty("--sidebar-width", validatedWidth)
  }

  isMobile() {
    if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
      return false
    }

    return window.matchMedia("(max-width: 767px)").matches
  }
}
