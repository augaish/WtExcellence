import { Controller } from "@hotwired/stimulus"

// Collapsible tree for the Org Structure / Process Architecture registers.
// Each toggle button owns the children container that carries the same
// data-parent-id, so expanding one branch never disturbs another.
export default class extends Controller {
  static targets = ["toggle", "children", "chevron"]

  toggle(event) {
    const button = event.currentTarget
    const nodeId = button.dataset.nodeId
    const container = this.childrenTargets.find((el) => el.dataset.parentId === nodeId)
    if (!container) return

    const willExpand = container.hidden
    container.hidden = !willExpand
    button.setAttribute("aria-expanded", String(willExpand))

    const chevron = button.querySelector("[data-org-tree-target='chevron']")
    if (chevron) chevron.textContent = willExpand ? "▾" : "▸"
  }

  expandAll() {
    this.setAll(true)
  }

  collapseAll() {
    this.setAll(false)
  }

  setAll(expanded) {
    this.childrenTargets.forEach((el) => { el.hidden = !expanded })
    this.toggleTargets.forEach((button) => {
      button.setAttribute("aria-expanded", String(expanded))
      const chevron = button.querySelector("[data-org-tree-target='chevron']")
      if (chevron) chevron.textContent = expanded ? "▾" : "▸"
    })
  }
}
