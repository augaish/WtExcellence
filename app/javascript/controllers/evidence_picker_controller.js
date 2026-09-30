import { Controller } from "@hotwired/stimulus"

// A ticked list of Library files: typing narrows the list, and the count of
// ticked files is shown under it.
export default class extends Controller {
  static targets = ["row", "summary"]

  filter(event) {
    const needle = event.target.value.trim().toLowerCase()
    this.rowTargets.forEach((row) => { row.hidden = Boolean(needle) && !(row.dataset.name || "").includes(needle) })
  }

  count() {
    const ticked = this.element.querySelectorAll("input[type=checkbox]:checked").length
    if (this.hasSummaryTarget) this.summaryTarget.textContent = ticked ? `✓ ${ticked}` : ""
  }
}
