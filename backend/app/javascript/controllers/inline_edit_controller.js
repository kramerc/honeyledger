import { Controller } from "@hotwired/stimulus"

// Manages inline editing of table rows.
// The controller lives on the <tr> element. Clicking "Edit" fetches the
// inline form HTML from the server and replaces the row's innerHTML.
// "Cancel" restores the original content. Form submission is handled by
// Turbo, with the server responding via Turbo Streams.
export default class extends Controller {
  static values = { url: String }

  edit(event) {
    event.preventDefault()
    this.cachedHTML = this.element.innerHTML

    fetch(this.urlValue, {
      headers: {
        "Accept": "text/html",
        "X-Requested-With": "XMLHttpRequest"
      }
    })
      .then(response => {
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        return response.text()
      })
      .then(html => {
        this.element.innerHTML = html
      })
  }

  cancel(event) {
    event.preventDefault()
    if (this.cachedHTML) {
      this.element.innerHTML = this.cachedHTML
      this.cachedHTML = null
    }
  }
}
