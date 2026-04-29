import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["name", "input", "pencil", "error"]
  static values = { url: String }

  start() {
    this.openEdit({ select: true })
  }

  openEdit({ select }) {
    if (!this.hasInputTarget) return
    const currentHref = this.element.getAttribute("href")
    if (currentHref != null) {
      this._originalHref = currentHref
      this.element.removeAttribute("href")
    }
    this.nameTarget.hidden = true
    this.pencilTarget.hidden = true
    this.inputTarget.hidden = false
    this.inputTarget.focus()
    if (select) {
      this.inputTarget.select()
    } else {
      const end = this.inputTarget.value.length
      this.inputTarget.setSelectionRange(end, end)
    }
    this._submitting = false
  }

  closeEdit() {
    if (!this.hasInputTarget) return
    this.inputTarget.hidden = true
    this.nameTarget.hidden = false
    this.pencilTarget.hidden = false
    if (this.hasErrorTarget) this.errorTarget.remove()
    if (this._originalHref != null) {
      this.element.setAttribute("href", this._originalHref)
      this._originalHref = null
    }
  }

  cancel() {
    this.inputTarget.value = this.nameTarget.textContent
    this.closeEdit()
  }

  async submit() {
    if (this._submitting) return
    if (this.inputTarget.hidden) return

    const newName = this.inputTarget.value.trim()
    const oldName = this.nameTarget.textContent.trim()

    if (newName === oldName) {
      this.closeEdit()
      return
    }
    if (newName === "") {
      this.cancel()
      return
    }

    this._submitting = true

    const body = new FormData()
    body.append("account[name]", newName)

    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Accept": "text/vnd.turbo-stream.html",
          "X-CSRF-Token": this._csrfToken()
        },
        body
      })
      const text = await response.text()
      if (response.ok) {
        this.nameTarget.textContent = newName
        this.closeEdit()
        if (text.trim().length > 0) Turbo.renderStreamMessage(text)
      } else {
        Turbo.renderStreamMessage(text)
      }
    } catch (error) {
      console.error("Inline rename failed", error)
    } finally {
      this._submitting = false
    }
  }

  inputTargetConnected(element) {
    if (element.getAttribute("aria-invalid") === "true") {
      this.openEdit({ select: false })
    }
  }

  _csrfToken() {
    const meta = document.querySelector("meta[name='csrf-token']")
    return meta ? meta.content : ""
  }
}
