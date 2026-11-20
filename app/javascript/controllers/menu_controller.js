import { Controller } from "@hotwired/stimulus"

// A small action menu behind a trigger button, built on the Popover API.
//
//   <div data-controller="menu">
//     <button type="button" popovertarget="ID" aria-haspopup="menu"
//             data-menu-target="trigger">…</button>
//     <div id="ID" popover role="menu" data-menu-target="menu"
//          data-action="beforetoggle->menu#beforeToggled toggle->menu#toggled
//                       keydown->menu#navigate click->menu#close">
//       <a role="menuitem" …>…</a>
//     </div>
//   </div>
//
// The browser does the rest: the popover sits in the top layer (so a
// scrolling container can't clip it), closes on an outside click or Escape,
// and hands focus back to the trigger, and CSS anchor positioning places it
// beside the trigger before the first paint (menu.css). This controller moves
// focus with the arrow keys, closes the menu once an item is chosen, and
// places it by script only where anchor positioning is missing.
export default class extends Controller {
  static targets = [ "trigger", "menu" ]

  // Gap between trigger and menu, and the least room kept from the viewport edge.
  static OFFSET = 4

  static anchorPositioning = CSS.supports("anchor-name: --menu")

  connect() {
    this.reposition = this.reposition.bind(this)
    this.dismiss = this.dismiss.bind(this)
  }

  disconnect() {
    this.stopTracking()
  }

  // Wired as beforetoggle->menu#beforeToggled. The toggle event only arrives
  // after the menu has painted, so where the script places it, keep it
  // invisible until then rather than let it jump into position.
  beforeToggled(event) {
    if (event.newState === "open" && !this.constructor.anchorPositioning) {
      this.menuTarget.classList.add("menu--placing")
    }
  }

  toggled(event) {
    if (event.newState === "open") {
      this.triggerTarget.setAttribute("aria-expanded", "true")
      this.reposition()
      this.menuTarget.classList.remove("menu--placing")
      this.startTracking()
      this.items[0]?.focus()
    } else {
      this.triggerTarget.setAttribute("aria-expanded", "false")
      this.stopTracking()
    }
  }

  // Choosing an item runs its own action (Turbo link, Stimulus action);
  // the menu just gets out of the way.
  close(event) {
    if (event.target.closest("[role=menuitem]")) this.menuTarget.hidePopover()
  }

  navigate(event) {
    const items = this.items
    if (items.length === 0) return

    const index = items.indexOf(document.activeElement)
    let next
    switch (event.key) {
      case "ArrowDown": next = items[(index + 1) % items.length]; break
      case "ArrowUp":   next = items[(index - 1 + items.length) % items.length]; break
      case "Home":      next = items[0]; break
      case "End":       next = items[items.length - 1]; break
      case "Tab":       this.menuTarget.hidePopover(); return
      default: return
    }
    event.preventDefault()
    next.focus()
  }

  // Right-align the menu under the trigger; flip it above when there isn't
  // room below.
  reposition() {
    if (this.constructor.anchorPositioning) return

    const offset = this.constructor.OFFSET
    const trigger = this.triggerTarget.getBoundingClientRect()
    const menu = this.menuTarget
    const { width, height } = menu.getBoundingClientRect()

    let top = trigger.bottom + offset
    if (top + height > window.innerHeight - offset && trigger.top - offset - height >= offset) {
      top = trigger.top - offset - height
    }
    const left = Math.max(offset, Math.min(trigger.right - width, window.innerWidth - width - offset))

    menu.style.top = `${top}px`
    menu.style.left = `${left}px`
  }

  // The menu is fixed to the viewport, so scrolling would leave it behind;
  // close it instead, as native menus do.
  dismiss(event) {
    if (!this.menuTarget.contains(event.target)) this.menuTarget.hidePopover()
  }

  startTracking() {
    window.addEventListener("scroll", this.dismiss, { capture: true, passive: true })
    window.addEventListener("resize", this.reposition, { passive: true })
  }

  stopTracking() {
    window.removeEventListener("scroll", this.dismiss, { capture: true })
    window.removeEventListener("resize", this.reposition)
  }

  get items() {
    return Array.from(this.menuTarget.querySelectorAll("[role=menuitem]"))
  }
}
