import { Controller } from "@hotwired/stimulus"

// Opens a unit's mandate when its box is clicked. The mandates are already on
// the page, one panel per unit, so selecting one is a matter of showing it —
// no request, and the chart stays usable without a round trip per click.
export default class extends Controller {
  static targets = ["panel", "placeholder"]

  select(event) {
    const node = event.currentTarget
    const unitId = node.dataset.orgChartUnitIdParam
    if (!unitId) return

    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.unitId !== unitId
    })

    if (this.hasPlaceholderTarget) this.placeholderTarget.hidden = true

    this.element.querySelectorAll(".org-chart-node rect:first-of-type").forEach((rect) => {
      rect.setAttribute("stroke", "#E3E3E3")
      rect.setAttribute("stroke-width", "1")
    })

    const selected = node.querySelector("rect")
    if (selected) {
      selected.setAttribute("stroke", "#5C3984")
      selected.setAttribute("stroke-width", "2")
    }
  }
}
