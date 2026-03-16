import { Controller } from "@hotwired/stimulus"

const ICONS  = { auto: "🖥️", light: "☀️", dark: "🌙" }
const LABELS = { auto: "Auto (system theme)", light: "Light theme", dark: "Dark theme" }
const CYCLE  = { auto: "light", light: "dark", dark: "auto" }

export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.applyTheme(this.savedTheme)
  }

  toggle() {
    const next = CYCLE[this.savedTheme]
    try {
      localStorage.setItem("theme", next)
    } catch (error) {
      // Ignore storage errors and still apply the theme
    }
    this.applyTheme(next)
  }

  get savedTheme() {
    try {
      return localStorage.getItem("theme") || "auto"
    } catch (error) {
      return "auto"
    }
  }

  applyTheme(theme) {
    if (theme === "auto") {
      document.documentElement.removeAttribute("data-theme")
    } else {
      document.documentElement.setAttribute("data-theme", theme)
    }
    if (this.hasButtonTarget) {
      this.buttonTarget.textContent = ICONS[theme]
      this.buttonTarget.title = LABELS[theme]
      this.buttonTarget.setAttribute("aria-label", LABELS[theme])
    }
  }
}
