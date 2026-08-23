import { Controller } from "@hotwired/stimulus"

// Lets a file be dragged onto the upload form. A dropped file is assigned to the
// existing <input type="file"> so the form submits exactly as if it were picked
// with the native file chooser. Without JavaScript the form is unchanged.
export default class extends Controller {
  static targets = ["input", "zone", "status"]
  static classes = ["active"]

  connect() {
    this.preventWindowDrop = (event) => {
      if (!this.zoneTarget.contains(event.target)) event.preventDefault()
    }
    window.addEventListener("dragover", this.preventWindowDrop)
    window.addEventListener("drop", this.preventWindowDrop)
  }

  disconnect() {
    window.removeEventListener("dragover", this.preventWindowDrop)
    window.removeEventListener("drop", this.preventWindowDrop)
  }

  dragover(event) {
    event.preventDefault()
    this.zoneTarget.classList.add(this.activeClass)
  }

  dragleave(event) {
    if (this.zoneTarget.contains(event.relatedTarget)) return
    this.zoneTarget.classList.remove(this.activeClass)
  }

  drop(event) {
    event.preventDefault()
    this.zoneTarget.classList.remove(this.activeClass)

    const files = event.dataTransfer.files
    if (files.length !== 1) {
      this.showMessage("Drop a single .csv file.")
      return
    }

    const file = files[0]
    if (!this.acceptable(file)) {
      this.showMessage(`${file.name} is not a .csv file.`)
      return
    }

    const transfer = new DataTransfer()
    transfer.items.add(file)
    this.inputTarget.files = transfer.files
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  // The native file input already displays the selected filename, so the
  // status line only carries rejection messages and is cleared on success.
  changed() {
    this.showMessage("")
  }

  acceptable(file) {
    const csvTypes = ["text/csv", "application/vnd.ms-excel"]
    return /\.csv$/i.test(file.name) || csvTypes.includes(file.type)
  }

  showMessage(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
