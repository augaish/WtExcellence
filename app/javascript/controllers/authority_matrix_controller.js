import { Controller } from "@hotwired/stimulus"

// The Authorities page: panels behind the top buttons, a search box that
// filters as each letter is typed, categories that fold, and drag to reorder
// them (the new order is saved as soon as the box is dropped).
export default class extends Controller {
  static targets = ["panel", "search", "list", "category", "body", "chevron", "noMatch"]
  static values = { reorderUrl: String }

  toggle(event) {
    const name = event.params.panel
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.panel === name ? !panel.hidden : true
    })
  }

  filter() {
    const needle = this.searchTarget.value.trim().toLowerCase()
    let shown = 0
    this.categoryTargets.forEach((section) => {
      const matches = !needle || (section.dataset.searchText || "").includes(needle)
      section.hidden = !matches
      if (matches) shown += 1
      // Inside a matching category, narrow to the authorities that match.
      section.querySelectorAll("[data-search-text]").forEach((row) => {
        if (row === section) return
        row.hidden = Boolean(needle) && !(row.dataset.searchText || "").includes(needle) && !(section.dataset.searchText || "").split(" ")[0].includes(needle)
      })
    })
    if (this.hasNoMatchTarget) this.noMatchTarget.hidden = shown > 0
  }

  toggleCategory(event) {
    const section = event.currentTarget.closest("[data-authority-matrix-target='category']")
    this.setOpen(section, section.querySelector("[data-authority-matrix-target='body']").hidden)
  }

  expandAll() { this.categoryTargets.forEach((s) => this.setOpen(s, true)) }
  collapseAll() { this.categoryTargets.forEach((s) => this.setOpen(s, false)) }

  setOpen(section, open) {
    const body = section.querySelector("[data-authority-matrix-target='body']")
    const button = section.querySelector("[aria-expanded]")
    const chevron = section.querySelector("[data-authority-matrix-target='chevron']")
    if (body) body.hidden = !open
    if (button) button.setAttribute("aria-expanded", String(open))
    if (chevron) chevron.textContent = open ? "▾" : "▸"
  }

  // ---- Drag to reorder --------------------------------------------------

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

  drop(event) {
    event.preventDefault()
  }

  dragEnd() {
    if (!this.dragged) return
    this.dragged.classList.remove("opacity-50")
    this.dragged = null
    this.renumber()
    this.save()
  }

  renumber() {
    let n = 0
    this.categoryTargets.forEach((section) => {
      if (!section.dataset.categoryId) return
      n += 1
      const number = section.querySelector("h2 .font-mono")
      if (number) number.textContent = String(n)
    })
  }

  save() {
    if (!this.reorderUrlValue) return
    const ids = this.categoryTargets.map((s) => s.dataset.categoryId).filter(Boolean)
    const token = document.querySelector("meta[name='csrf-token']")?.content
    fetch(this.reorderUrlValue, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token, Accept: "application/json" },
      body: JSON.stringify({ ids })
    })
  }
}
