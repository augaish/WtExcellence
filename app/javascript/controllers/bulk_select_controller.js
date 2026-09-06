import { Controller } from "@hotwired/stimulus"

// Checklist with a header "select all" that is a TRUE TOGGLE.
//
// The source platform shipped a header checkbox that could only ever turn rows
// ON — unticking it did nothing, so users had to deselect one row at a time.
// Here the header is driven by its own checked state, and it also reflects the
// rows: it shows indeterminate on a partial selection and unticks itself when
// the last row is cleared.
export default class extends Controller {
  static targets = ["header", "row", "count", "submit"]

  connect() {
    this.sync()
  }

  toggleAll(event) {
    const checked = event.currentTarget.checked
    this.rowTargets.forEach((row) => { row.checked = checked })
    this.sync()
  }

  rowChanged() {
    this.sync()
  }

  sync() {
    const total = this.rowTargets.length
    const selected = this.rowTargets.filter((row) => row.checked).length

    if (this.hasHeaderTarget) {
      this.headerTarget.checked = total > 0 && selected === total
      this.headerTarget.indeterminate = selected > 0 && selected < total
    }
    if (this.hasCountTarget) {
      this.countTarget.textContent = String(selected)
    }
    this.submitTargets.forEach((button) => {
      button.disabled = selected === 0
      button.classList.toggle("opacity-50", selected === 0)
      button.classList.toggle("cursor-not-allowed", selected === 0)
    })
  }
}
