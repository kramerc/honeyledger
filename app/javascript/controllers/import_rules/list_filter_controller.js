import { Controller } from "@hotwired/stimulus"

// Client-side search + segment (All / Assign / Exclude) filtering of the rule list.
// Rule lists are small and fully rendered, so we just show/hide rows.
export default class extends Controller {
  static targets = ["search", "segment", "row", "count"]

  initialize() {
    this.segment = "all"
  }

  connect() {
    this.apply()
  }

  filter() {
    this.apply()
  }

  selectSegment(event) {
    this.segment = event.currentTarget.dataset.segment
    this.segmentTargets.forEach(button => button.classList.toggle("active", button === event.currentTarget))
    this.apply()
  }

  // Highlight the row whose editor is open (the list isn't re-rendered on selection).
  select(event) {
    const row = event.currentTarget.closest(".ir-rule")
    this.rowTargets.forEach(candidate => candidate.classList.toggle("ir-rule--selected", candidate === row))
  }

  // Re-apply whenever rows are swapped in by a Turbo Stream (create/update/destroy).
  rowTargetConnected() {
    this.apply()
  }

  apply() {
    const query = (this.hasSearchTarget ? this.searchTarget.value : "").trim().toLowerCase()
    let visible = 0

    this.rowTargets.forEach(row => {
      const matchesQuery = !query || (row.dataset.search || "").includes(query)
      const isExclude = row.dataset.irExclude === "true"
      const matchesSegment = this.segment === "all" || (this.segment === "exclude") === isExclude
      const show = matchesQuery && matchesSegment

      row.hidden = !show
      if (show) visible += 1
    })

    if (this.hasCountTarget) this.countTarget.textContent = visible
  }
}
