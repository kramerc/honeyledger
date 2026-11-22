import { Controller } from "@hotwired/stimulus"

// The lazy frame at the foot of a page of the transactions index, which loads
// the next page as it scrolls into view (transactions/_page).
export default class extends Controller {
  // Start the next page below the last row actually on screen, not the row
  // that was last when this frame rendered: that row may since have been
  // deleted, merged away or moved, and a row added in its place would fall
  // between the two and never load. The rows on screen stay in sorted order,
  // since every insertion goes through transactions/_insert.
  rebase(event) {
    if (event.target !== this.element) return // a row's own lazy edit frame

    const rows = document.querySelectorAll("#transactions [data-page-cursor]")
    const last = rows[rows.length - 1]
    if (!last) return

    const url = event.detail.url
    new URLSearchParams(last.dataset.pageCursor).forEach((value, key) => url.searchParams.set(key, value))
  }

  // A row already on screen may come back in the page, when a Turbo Stream
  // inserted it while the page was loading. Keep the one already placed, so
  // no DOM id appears twice.
  skipLoaded(event) {
    if (event.target !== this.element) return

    event.detail.newFrame.querySelectorAll("[data-page-cursor]").forEach((row) => {
      const frame = row.closest("turbo-frame")
      if (frame?.id && document.getElementById(frame.id)) frame.remove()
    })
  }
}
