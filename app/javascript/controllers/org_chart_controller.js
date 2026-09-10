import { Controller } from "@hotwired/stimulus"

// Opens a unit's mandate when its box is clicked. The mandates are already on
// the page, one panel per unit, so selecting one is a matter of showing it —
// no request, and the chart stays usable without a round trip per click.
export default class extends Controller {
  static targets = ["panel", "placeholder", "details", "canvas", "search", "noMatch"]

  connect() {
    this.scale = 1
    this.hidden = new Set()
    // A large structure opens on its top two levels; the rest unfolds on demand.
    if (this.nodes().length > 24) this.collapseToTop()
    requestAnimationFrame(() => this.fit())
  }

  nodes() { return Array.from(this.element.querySelectorAll(".org-chart-node")) }
  nodeFor(id) { return this.element.querySelector(`.org-chart-node[data-unit-id="${id}"]`) }
  childrenOf(id) { return this.nodes().filter((n) => n.dataset.parentId === id) }
  depthOf(node) {
    let depth = 0
    let current = node
    while (current && current.dataset.parentId) {
      current = this.nodeFor(current.dataset.parentId)
      depth += 1
    }
    return depth
  }

  // ---- Fit: scale the drawing so the whole visible chart fits the frame.
  fit() {
    if (!this.hasCanvasTarget) return
    const svg = this.canvasTarget.querySelector("svg")
    const frame = this.canvasTarget.parentElement
    if (!svg || !frame) return
    const width = parseFloat(svg.getAttribute("width")) || svg.getBoundingClientRect().width
    if (!width) return
    this.zoom(Math.min(1, (frame.clientWidth - 32) / width))
  }

  // ---- Search: highlight matches, reveal their branch, dim everything else.
  search() {
    const needle = this.searchTarget.value.trim().toLowerCase()
    let matches = 0
    this.nodes().forEach((node) => {
      const hit = needle && (node.dataset.searchText || "").includes(needle)
      node.style.opacity = needle && !hit ? "0.25" : "1"
      if (hit) { matches += 1; this.reveal(node.dataset.unitId) }
    })
    if (this.hasNoMatchTarget) this.noMatchTarget.hidden = !needle || matches > 0
  }

  reveal(id) {
    let node = this.nodeFor(id)
    while (node) {
      this.setBranch(node.dataset.unitId, true, false)
      node = this.nodeFor(node.dataset.parentId)
    }
    this.nodeFor(id)?.scrollIntoView({ block: "center", inline: "center", behavior: "smooth" })
  }

  // ---- Folding: a unit's descendants and their lines hide together.
  setBranch(id, open, recurse = true) {
    this.childrenOf(id).forEach((child) => {
      const cid = child.dataset.unitId
      child.style.display = open ? "" : "none"
      const line = this.element.querySelector(`path[data-child-id="${cid}"]`)
      if (line) line.style.display = open ? "" : "none"
      if (!open || recurse) this.setBranch(cid, open, recurse)
    })
  }

  collapseToTop() {
    this.nodes().forEach((node) => { if (this.depthOf(node) >= 1) this.setBranch(node.dataset.unitId, false) })
  }

  expandAllBranches() {
    this.nodes().forEach((node) => this.setBranch(node.dataset.unitId, true, false))
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
    this.setBranch(unitId, true, false)

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
