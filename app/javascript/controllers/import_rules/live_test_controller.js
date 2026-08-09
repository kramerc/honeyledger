import { Controller } from "@hotwired/stimulus"

// Drives the editor's live "matches in your ledger" panel and keeps the Preview button's
// modal URL in sync with the draft. Debounces edits to the form, then points the
// ir_match_preview Turbo Frame (and the Preview modal trigger) at the current pattern /
// match type / account / exclude. A loading indicator is shown only if a fetch is slow,
// so fast queries don't flash — the previous results stay put until the new ones arrive.
export default class extends Controller {
  static targets = ["frame", "previewButton"]
  static values = { url: String, previewUrl: String, ruleId: String, delay: { type: Number, default: 250 } }

  connect() {
    this.stopLoading = this.stopLoading.bind(this)
    if (this.hasFrameTarget) {
      this.frameTarget.addEventListener("turbo:frame-load", this.stopLoading)
      this.frameTarget.addEventListener("turbo:fetch-request-error", this.stopLoading)
    }
    this.syncPreviewButton()
    // The live-match frame is preloaded server-side when the form renders, so don't refetch
    // on connect — only when the draft actually changes (see update()).
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
    if (this.loadingTimer) clearTimeout(this.loadingTimer)
    if (this.hasFrameTarget) {
      this.frameTarget.removeEventListener("turbo:frame-load", this.stopLoading)
      this.frameTarget.removeEventListener("turbo:fetch-request-error", this.stopLoading)
    }
  }

  update() {
    // The Preview button URL is just a string, so keep it current immediately; only the
    // live-match Turbo Frame fetch is debounced.
    this.syncPreviewButton()
    if (this.timer) clearTimeout(this.timer)
    this.timer = setTimeout(() => this.run(), this.delayValue)
  }

  run() {
    if (!this.hasFrameTarget) return

    this.indicateLoadingSoon()
    this.frameTarget.src = `${this.urlValue}?${this.draftParams().toString()}`
  }

  // Reveal the spinner/dim only if the fetch is actually slow, so fast loads don't flicker.
  indicateLoadingSoon() {
    if (this.loadingTimer) clearTimeout(this.loadingTimer)
    this.loadingTimer = setTimeout(() => {
      if (this.hasFrameTarget) this.frameTarget.classList.add("ir-test-frame--loading")
    }, 150)
  }

  // Clear the loading indicator when the fetch finishes — whether it loaded or errored.
  stopLoading() {
    if (this.loadingTimer) clearTimeout(this.loadingTimer)
    if (this.hasFrameTarget) this.frameTarget.classList.remove("ir-test-frame--loading")
  }

  syncPreviewButton() {
    if (this.hasPreviewButtonTarget && this.hasPreviewUrlValue) {
      this.previewButtonTarget.setAttribute("data-import-rules--modal-src-param", `${this.previewUrlValue}?${this.draftParams().toString()}`)
    }
  }

  draftParams() {
    const params = new URLSearchParams()
    params.set("pattern", this.fieldValue("match_pattern"))
    params.set("match_type", this.checkedValue("match_type") || "contains")

    const account = this.fieldValue("account_id")
    if (account) params.set("account_id", account)

    params.set("exclude", this.checkedValue("exclude") === "true" ? "true" : "false")

    // The saved rule id lets the preview tell whether the draft has unsaved edits.
    if (this.hasRuleIdValue && this.ruleIdValue) params.set("id", this.ruleIdValue)
    return params
  }

  fieldValue(attribute) {
    const field = this.element.querySelector(`[name="import_rule[${attribute}]"]`)
    return field ? field.value : ""
  }

  checkedValue(attribute) {
    const field = this.element.querySelector(`[name="import_rule[${attribute}]"]:checked`)
    return field ? field.value : ""
  }
}
