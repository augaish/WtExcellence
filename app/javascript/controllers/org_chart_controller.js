import { Controller } from "@hotwired/stimulus"

// Opens a unit's mandate when its box is clicked. The mandates are already on
// the page, one panel per unit, so selecting one is a matter of showing it —
// no request, and the chart stays usable without a round trip per click.
export default class extends Controller {
  static targets = ["panel", "placeholder", "details", "canvas", "search", "noMatch"]

  // The same measures the server lays the chart out with.
  static BOX_WIDTH = 190
  static BOX_HEIGHT = 68
  static H_GAP = 18
  static V_GAP = 64
  static PADDING = 24

  connect() {
    this.scale = 1
    this.hidden = new Set()
    this.rememberOrigins()
    // A large structure opens on its top two levels; the rest unfolds on demand.
    if (this.nodes().length > 24) this.collapseToTop()
    this.relayout()
    requestAnimationFrame(() => this.fit())
  }

  // Where the server drew each box; moving a box is a translation from here.
  rememberOrigins() {
    this.origin = {}
    this.nodes().forEach((node) => {
      const rect = node.querySelector("rect")
      this.origin[node.dataset.unitId] = { x: parseFloat(rect.getAttribute("x")), y: parseFloat(rect.getAttribute("y")) }
    })
  }

  visible(node) { return node.style.display !== "none" }
  visibleChildrenOf(id) { return this.childrenOf(id).filter((n) => this.visible(n)) }

  // A tidy tree over the boxes that are showing: a leaf takes one column, a
  // parent is centred over its visible children. Folded branches stop
  // stretching the row above them.
  relayout() {
    const C = this.constructor
    const svg = this.canvasTarget?.querySelector("svg")
    if (!svg) return
    const roots = this.nodes().filter((n) => this.visible(n) && !this.nodeFor(n.dataset.parentId))
    const positions = {}
    const place = (node, depth, cursor) => {
      const id = node.dataset.unitId
      const y = C.PADDING + depth * (C.BOX_HEIGHT + C.V_GAP)
      const kids = this.visibleChildrenOf(id)
      if (kids.length === 0) {
        positions[id] = { x: cursor, y }
        return cursor + C.BOX_WIDTH
      }
      const start = cursor
      let childCursor = cursor
      kids.forEach((kid, i) => {
        if (i > 0) childCursor += C.H_GAP
        childCursor = place(kid, depth + 1, childCursor)
      })
      const centre = start + (childCursor - start) / 2 - C.BOX_WIDTH / 2
      positions[id] = { x: Math.max(centre, start), y }
      return Math.max(childCursor, positions[id].x + C.BOX_WIDTH)
    }
    let cursor = C.PADDING
    roots.forEach((root) => { cursor = place(root, 0, cursor) + C.H_GAP })

    let maxX = 0, maxY = 0
    Object.entries(positions).forEach(([id, pos]) => {
      const node = this.nodeFor(id)
      const from = this.origin[id]
      node.setAttribute("transform", `translate(${pos.x - from.x}, ${pos.y - from.y})`)
      maxX = Math.max(maxX, pos.x + C.BOX_WIDTH)
      maxY = Math.max(maxY, pos.y + C.BOX_HEIGHT)
      const line = this.element.querySelector(`path[data-child-id="${id}"]`)
      const parent = positions[node.dataset.parentId]
      if (line && parent) {
        const childX = pos.x + C.BOX_WIDTH / 2
        const parentX = parent.x + C.BOX_WIDTH / 2
        const parentBottom = parent.y + C.BOX_HEIGHT
        const elbow = parentBottom + C.V_GAP / 2
        line.setAttribute("d", `M ${parentX} ${parentBottom} V ${elbow} H ${childX} V ${pos.y}`)
      }
    })
    const width = maxX + C.PADDING, height = maxY + C.PADDING
    svg.setAttribute("width", width)
    svg.setAttribute("height", height)
    svg.setAttribute("viewBox", `0 0 ${width} ${height}`)
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
    this.relayout()
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
    this.relayout()
    this.fit()
  }

  expandAllBranches() {
    this.nodes().forEach((node) => this.setBranch(node.dataset.unitId, true, false))
    this.relayout()
    this.fit()
  }

  // First click on a unit selects it and opens its children; a click on the
  // unit already selected folds them again.
  select(event) {
    const node = event.currentTarget
    const unitId = node.dataset.orgChartUnitIdParam
    if (!unitId) return

    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.unitId !== unitId
    })

    if (this.hasPlaceholderTarget) this.placeholderTarget.hidden = true
    if (this.hasDetailsTarget) this.detailsTarget.hidden = false
    const childrenOpen = this.visibleChildrenOf(unitId).length > 0
    if (this.selectedId === unitId && childrenOpen) {
      this.setBranch(unitId, false)
    } else {
      this.setBranch(unitId, true, false)
    }
    this.selectedId = unitId
    this.relayout()

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
    this.selectedId = null
  }

  // ---- Zoom: the drawing scales in steps between half and triple size.
  zoomIn() { this.zoom(this.scale + 0.2) }
  zoomOut() { this.zoom(this.scale - 0.2) }

  zoom(next) {
    this.scale = Math.min(3, Math.max(0.5, Math.round(next * 10) / 10))
    if (this.hasCanvasTarget) this.canvasTarget.style.transform = `scale(${this.scale})`
  }
}
