import { Controller } from "@hotwired/stimulus"

// The diagram's boxes can be dragged into a new order, in the picture or in
// the element list. The order is saved as soon as a box is dropped; the
// server renumbers the linked steps and redraws the arrows, and the page
// reloads to show the result.
export default class extends Controller {
  static targets = ["picture", "list"]
  static values = { url: String, bendUrl: String }

  connect() {
    if (!this.urlValue) return
    this.bindPicture()
    this.bindBends()
  }

  // ---- Arrows: drag the small handle to bend an arrow; double-click to straighten.

  bindBends() {
    if (!this.hasPictureTarget || !this.bendUrlValue) return
    this.pictureTarget.querySelectorAll(".diagram-bend").forEach((handle) => {
      handle.setAttribute("opacity", "1")
      handle.addEventListener("pointerdown", (event) => this.bendDown(event, handle))
      handle.addEventListener("dblclick", () => this.saveBend(handle.dataset.flowId, null, null))
    })
  }

  bendDown(event, handle) {
    event.preventDefault()
    event.stopPropagation()
    const svg = this.pictureTarget.querySelector("svg")
    const scale = svg.viewBox.baseVal.width / svg.getBoundingClientRect().width
    const start = { x: event.clientX, y: event.clientY, cx: parseFloat(handle.getAttribute("cx")), cy: parseFloat(handle.getAttribute("cy")) }
    let moved = false
    const move = (e) => {
      moved = true
      handle.setAttribute("cx", start.cx + (e.clientX - start.x) * scale)
      handle.setAttribute("cy", start.cy + (e.clientY - start.y) * scale)
    }
    const up = () => {
      window.removeEventListener("pointermove", move)
      window.removeEventListener("pointerup", up)
      if (!moved) return
      const dx = Math.round(parseFloat(handle.getAttribute("cx")) - parseFloat(handle.dataset.midX))
      const dy = Math.round(parseFloat(handle.getAttribute("cy")) - parseFloat(handle.dataset.midY))
      this.saveBend(handle.dataset.flowId, dx, dy)
    }
    window.addEventListener("pointermove", move)
    window.addEventListener("pointerup", up)
  }

  saveBend(flowId, dx, dy) {
    const token = document.querySelector("meta[name='csrf-token']")?.content
    fetch(this.bendUrlValue.replace("FLOW", flowId), {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token, Accept: "application/json" },
      body: JSON.stringify({ dx, dy })
    }).then((response) => { if (response.ok) window.location.reload() })
  }

  // ---- The picture: pointer drag along the row --------------------------

  bindPicture() {
    if (!this.hasPictureTarget) return
    this.pictureTarget.querySelectorAll(".diagram-node").forEach((node) => {
      node.addEventListener("pointerdown", (event) => this.pictureDown(event, node))
    })
  }

  pictureDown(event, node) {
    event.preventDefault()
    const svg = this.pictureTarget.querySelector("svg")
    const scale = svg.viewBox.baseVal.width / svg.getBoundingClientRect().width
    this.drag = { node, startX: event.clientX, scale, moved: false }
    node.style.cursor = "grabbing"
    const move = (e) => {
      const dx = (e.clientX - this.drag.startX) * this.drag.scale
      if (Math.abs(dx) > 2) this.drag.moved = true
      node.setAttribute("transform", `translate(${dx}, 0)`)
    }
    const up = () => {
      window.removeEventListener("pointermove", move)
      window.removeEventListener("pointerup", up)
      node.style.cursor = "grab"
      if (this.drag.moved) this.saveFromPicture()
      else node.removeAttribute("transform")
      this.drag = null
    }
    window.addEventListener("pointermove", move)
    window.addEventListener("pointerup", up)
  }

  // Where each box now sits, left to right, is the new order.
  saveFromPicture() {
    const nodes = Array.from(this.pictureTarget.querySelectorAll(".diagram-node"))
    const centre = (node) => {
      const shift = node.transform.baseVal.numberOfItems ? node.transform.baseVal.getItem(0).matrix.e : 0
      return parseFloat(node.dataset.x) + parseFloat(node.dataset.width) / 2 + shift
    }
    const ids = nodes.sort((a, b) => centre(a) - centre(b)).map((n) => n.dataset.elementId)
    this.save(ids)
  }

  // ---- The list: HTML drag and drop --------------------------------------

  dragStart(event) {
    this.dragged = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    this.dragged.classList.add("opacity-50")
  }

  dragOver(event) {
    event.preventDefault()
    const over = event.currentTarget
    if (!this.dragged || over === this.dragged) return
    const rect = over.getBoundingClientRect()
    const after = event.clientY > rect.top + rect.height / 2
    over.parentNode.insertBefore(this.dragged, after ? over.nextSibling : over)
  }

  drop(event) { event.preventDefault() }

  dragEnd() {
    if (!this.dragged) return
    this.dragged.classList.remove("opacity-50")
    this.dragged = null
    const items = Array.from(this.listTarget.querySelectorAll("li[data-element-id]"))
    items.forEach((li, i) => { const n = li.querySelector("[data-order-number]"); if (n) n.textContent = String(i + 1) })
    this.save(items.map((li) => li.dataset.elementId))
  }

  save(ids) {
    const token = document.querySelector("meta[name='csrf-token']")?.content
    fetch(this.urlValue, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token, Accept: "application/json" },
      body: JSON.stringify({ ids })
    }).then((response) => { if (response.ok) window.location.reload() })
  }
}
