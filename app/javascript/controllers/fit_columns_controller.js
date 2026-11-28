import { Controller } from "@hotwired/stimulus"

// Shows a table's optional columns only when they fit without scrolling
// sideways. Whether they fit depends on the figures (an eight-decimal BTC
// balance is far wider than a small one), so a fixed breakpoint either hides
// them with room to spare or lets the table overflow.
//
// The wrapper ends in one of two states: the full class (every column shown)
// or the compact class (optional columns hidden). The stylesheet picks a
// default for the first paint, before this controller connects.
//
// The controller sits on the element whose width the viewport sets (the
// section), never on the table's fit-content wrapper: that wrapper narrows
// when the columns go, and observing it would flip the state back and forth.
export default class extends Controller {
  static targets = ["wrapper"]
  static classes = ["full", "compact"]

  connect() {
    this.width = null
    this.observer = new ResizeObserver(([entry]) => {
      // Only a change of width can change what fits. Ignoring height also
      // ignores the section resizing because of the switch itself, such as
      // the wrapper's horizontal scrollbar appearing or going.
      const width = entry.contentRect.width
      if (width === this.width) return

      this.width = width
      // Out of the observer callback, so the layout change from switching
      // classes doesn't trip a "ResizeObserver loop" error.
      cancelAnimationFrame(this.frame)
      this.frame = requestAnimationFrame(() => this.fit())
    })
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
    cancelAnimationFrame(this.frame)
  }

  fit() {
    if (!this.hasWrapperTarget) return

    const wrapper = this.wrapperTarget
    wrapper.classList.remove(this.compactClass)
    wrapper.classList.add(this.fullClass)

    // A pixel of slack: engines round fractional widths differently, and a
    // fit-content wrapper is always exactly as wide as its table.
    if (wrapper.scrollWidth - wrapper.clientWidth > 1) {
      wrapper.classList.remove(this.fullClass)
      wrapper.classList.add(this.compactClass)
    }
  }
}
