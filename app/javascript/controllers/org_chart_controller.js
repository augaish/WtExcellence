import { Controller } from "@hotwired/stimulus"

// Opens a unit's mandate when its box is clicked. The mandates are already on
// the page, one panel per unit, so selecting one is a matter of showing it —
// no request, and the chart stays usable without a round trip per click.
export default class extends Controller {
  static targets = ["panel", "placeholder", "details", "canvas"]

  connect() {
    this.scale = 1
  }

  select(event) {
    const node = event.currentTarget
    const unitId = node.dataset.orgChartUnitIdParam
    if (!unitId) return

    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.unitId !== unitId
    })

    if (this.hasPlaceholderTarget) this.placeholderTarget.hidden = true
    if (this.hasDetailsTarget) this.detailsTarget.hidden = false

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

  close() {
    if (this.hasDetailsTarget) this.detailsTarget.hidden = true
    this.panelTargets.forEach((panel) => { panel.hidden = true })
  }

  // ---- Zoom: the drawing scales in steps between half and triple size.
  zoomIn() { this.zoom(this.scale + 0.2) }
  zoomOut() { this.zoom(this.scale - 0.2) }

  zoom(next) {
    this.scale = Math.min(3, Math.max(0.5, Math.round(next * 10) / 10))
    if (this.hasCanvasTarget) this.canvasTarget.style.transform = `scale(${this.scale})`
  }
}
