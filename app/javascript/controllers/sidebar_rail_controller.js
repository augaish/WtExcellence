import { Controller } from "@hotwired/stimulus"

// The sidebar rail: collapsed to icons, it opens while the pointer is over
// it or a link inside has keyboard focus, and stays open when pinned. The
// pin is remembered in this browser. Typing in the search box narrows the
// menu to matching items.
export default class extends Controller {
  static targets = ["search", "item", "section", "empty", "pin", "pinLabel"]
  static KEY = "wte.sidebar.pinned"

  connect() {
    this.pinned = this.read()
    this.hovered = false
    this.focused = false
    this.render()
  }

  enter(event) { if (event.pointerType !== "touch") { this.hovered = true; this.render() } }
  leave() { this.hovered = false; this.render() }
  focus() { this.focused = true; this.render() }
  blur(event) { if (!this.element.contains(event.relatedTarget)) { this.focused = false; this.render() } }

  pin() {
    this.pinned = !this.pinned
    this.write(this.pinned)
    this.render()
  }

  search() {
    const needle = this.searchTarget.value.trim().toLowerCase()
    let shown = 0
    this.itemTargets.forEach((item) => {
      const hit = !needle || (item.dataset.label || "").includes(needle)
      item.hidden = !hit
      if (hit) shown += 1
    })
    this.sectionTargets.forEach((section) => {
      section.hidden = Boolean(needle) && !Array.from(section.querySelectorAll("[data-sidebar-rail-target='item']")).some((i) => !i.hidden)
    })
    if (this.hasEmptyTarget) this.emptyTarget.hidden = shown > 0
  }

  render() {
    const open = this.pinned || this.hovered || this.focused
    this.element.dataset.expanded = String(open)
    if (this.hasPinTarget) {
      this.pinTarget.setAttribute("aria-pressed", String(this.pinned))
      if (this.hasPinLabelTarget) this.pinLabelTarget.textContent = this.pinned ? this.pinTarget.dataset.unpinText || this.pinLabelTarget.textContent : this.pinTarget.dataset.pinText || this.pinLabelTarget.textContent
    }
  }

  read() { try { return localStorage.getItem(this.constructor.KEY) === "1" } catch { return false } }
  write(value) { try { localStorage.setItem(this.constructor.KEY, value ? "1" : "0") } catch {} }
}
