import { Controller } from "@hotwired/stimulus"

// The Authorities page: panels behind the top buttons, a search box that
// filters as each letter is typed, categories that fold, drag to reorder the
// categories, and drag to reorder an authority or move it into another
// category (each new order is saved as soon as the row is dropped). A Fix
// link in the findings opens the category and lands on the authority.
export default class extends Controller {
  static targets = ["panel", "search", "list", "category", "body", "chevron", "noMatch", "rows", "authority"]
  static values = { reorderUrl: String, reorderAuthoritiesUrl: String }

  connect() {
    if (window.location.hash) this.revealHash()
  }

  // The findings list links to #authority-<id>; open its category and mark it.
  reveal(event) {
    const id = event.params.id
    const row = document.getElementById(`authority-${id}`)
    if (!row) return
    event.preventDefault()
    this.setOpen(row.closest("[data-authority-matrix-target='category']"), true)
    row.scrollIntoView({ behavior: "smooth", block: "center" })
    row.classList.add("ring-2", "ring-[#5C3984]")
    setTimeout(() => row.classList.remove("ring-2", "ring-[#5C3984]"), 2500)
  }

  revealHash() {
    const id = window.location.hash.replace("#authority-", "")
    this.reveal({ params: { id }, preventDefault() {} })
  }

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

  // ---- Authorities: within a category, or into another ------------------

  authorityDragStart(event) {
    event.stopPropagation()
    this.draggedAuthority = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    this.draggedAuthority.classList.add("opacity-50")
  }

  authorityDragOver(event) {
    if (!this.draggedAuthority) return
    event.preventDefault()
    event.stopPropagation()
    const over = event.currentTarget
    if (over === this.draggedAuthority) return
    const rect = over.getBoundingClientRect()
    const after = event.clientY > rect.top + rect.height / 2
    over.parentNode.insertBefore(this.draggedAuthority, after ? over.nextSibling : over)
  }

  // Dropping onto an empty part of a category puts the row at its end.
  rowsDragOver(event) {
    if (!this.draggedAuthority) return
    event.preventDefault()
    event.stopPropagation()
    const rows = event.currentTarget
    if (!rows.contains(this.draggedAuthority)) rows.appendChild(this.draggedAuthority)
  }

  authorityDrop(event) {
    if (!this.draggedAuthority) return
    event.preventDefault()
    event.stopPropagation()
  }

  authorityDragEnd() {
    if (!this.draggedAuthority) return
    this.draggedAuthority.classList.remove("opacity-50")
    const rows = this.draggedAuthority.closest("[data-authority-matrix-target='rows']")
    this.draggedAuthority = null
    this.renumberAuthorities()
    this.saveAuthorities(rows)
  }

  renumberAuthorities() {
    this.categoryTargets.forEach((section) => {
      const rows = section.querySelector("[data-authority-matrix-target='rows']")
      if (!rows) return
      const empty = section.querySelector("[data-empty]")
      const count = rows.querySelectorAll("[data-authority-matrix-target='authority']").length
      if (empty) empty.hidden = count > 0
      rows.querySelectorAll("[data-authority-matrix-target='authority']").forEach((row, i) => {
        const number = row.querySelector("[data-number]")
        if (number) number.textContent = `${section.dataset.categoryNumber || 0}.${i + 1}`
      })
    })
  }

  saveAuthorities(rows) {
    if (!this.reorderAuthoritiesUrlValue || !rows) return
    const ids = Array.from(rows.querySelectorAll("[data-authority-matrix-target='authority']")).map((r) => r.dataset.authorityId)
    const categoryId = rows.closest("[data-authority-matrix-target='category']").dataset.categoryId
    const token = document.querySelector("meta[name='csrf-token']")?.content
    fetch(this.reorderAuthoritiesUrlValue, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token, Accept: "application/json" },
      body: JSON.stringify({ ids, category_id: categoryId })
    })
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
      section.dataset.categoryNumber = String(n)
    })
    this.renumberAuthorities()
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
