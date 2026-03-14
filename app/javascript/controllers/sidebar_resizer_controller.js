import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sidebar"]

  connect() {
    const saved = localStorage.getItem("sidebarWidth")
    if (saved) {
      this.sidebarTarget.style.width = saved
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
    if (width < 100 || width > 500) return
    this.sidebarTarget.style.width = `${width}px`
  }

  stopResize() {
    document.removeEventListener("mousemove", this._onMouseMove)
    document.removeEventListener("mouseup", this._onMouseUp)
    document.body.style.userSelect = ""
    document.body.style.cursor = ""
    localStorage.setItem("sidebarWidth", this.sidebarTarget.style.width)
  }
}
