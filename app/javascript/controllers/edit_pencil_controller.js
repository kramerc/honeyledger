import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  navigate(event) {
    event.preventDefault()
    event.stopPropagation()
    Turbo.visit(this.urlValue)
  }
}
