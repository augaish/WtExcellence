import { Controller } from "@hotwired/stimulus"

// Updates the Min/Max column headers of a checkpoint's subcheckpoint table
// based on the scoring types selected across its (non-destroyed) rows.
//
// - All rows "Number"          → [Min Score]   [Max Score]
// - All rows "Percentage"      → [Min %]       [Max %]
// - All rows "Multiple Choice" → [Choices]     (merged, colspan=2)
// - Mixed / none               → [Min Score]   [Max Score]  (fallback)
export default class extends Controller {
  static targets = ["minHeader", "maxHeader"]
  static values = {
    minScore: String,
    maxScore: String,
    minPercentage: String,
    maxPercentage: String,
    choices: String,
  }

  connect() {
    this._onChange = this._onChange.bind(this)
    this.element.addEventListener("change", this._onChange)
    // Initial paint after Choices.js finishes wrapping the selects
    setTimeout(() => this.recompute(), 100)
  }

  disconnect() {
    this.element.removeEventListener("change", this._onChange)
  }

  _onChange(event) {
    if (event.target.matches('select[name*="[scoring_type]"]')) {
      this.recompute()
    }
  }

  recompute() {
    if (!this.hasMinHeaderTarget || !this.hasMaxHeaderTarget) return

    const selects = this.element.querySelectorAll('select[name*="[scoring_type]"]')
    const types = new Set()

    selects.forEach((sel) => {
      const row = sel.closest("[data-nested-form-wrapper]")
      if (row) {
        const destroy = row.querySelector('input[name*="_destroy"]')
        if (destroy && destroy.value === "1") return
      }
      if (sel.value) types.add(sel.value)
    })

    if (types.size === 1) {
      const [type] = [...types]
      if (type === "Percentage") {
        this._setHeaders(this.minPercentageValue, this.maxPercentageValue)
        return
      }
      if (type === "Multiple Choice") {
        this._mergeHeader(this.choicesValue)
        return
      }
    }

    this._setHeaders(this.minScoreValue, this.maxScoreValue)
  }

  _setHeaders(minLabel, maxLabel) {
    this.minHeaderTarget.textContent = minLabel
    this.minHeaderTarget.removeAttribute("colspan")
    this.maxHeaderTarget.style.display = ""
    this.maxHeaderTarget.textContent = maxLabel
  }

  _mergeHeader(label) {
    this.minHeaderTarget.textContent = label
    this.minHeaderTarget.setAttribute("colspan", "2")
    this.minHeaderTarget.classList.add("text-center")
    this.maxHeaderTarget.style.display = "none"
  }
}
