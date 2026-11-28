import { Controller } from "@hotwired/stimulus"

// Drops a table's optional columns only when they would make it scroll
// sideways. Whether they fit depends on the figures (an eight-decimal BTC
// balance is far wider than a small one), so a fixed breakpoint either hides
// them with room to spare or lets the table overflow.
//
// The controller sits on the element whose width the viewport sets (the
// section), never on the table's fit-content wrapper: that wrapper narrows
// when the columns go, and observing it would flip the class back and forth.
export default class extends Controller {
  static targets = ["wrapper"]
  static classes = ["compact"]

  connect() {
    this.observer = new ResizeObserver(() => this.fit())
    this.observer.observe(this.element)
    this.fit()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  fit() {
    const wrapper = this.wrapperTarget
    wrapper.classList.remove(this.compactClass)
    if (wrapper.scrollWidth > wrapper.clientWidth) {
      wrapper.classList.add(this.compactClass)
    }
  }
}
