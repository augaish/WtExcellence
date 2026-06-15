import { Controller } from "@hotwired/stimulus"

// Real-time overall score preview for the assessment page scoring section.
// Mirrors the backend ClauseScoreCalculator weighted-sum + cap formula.
//
// Number-type inputs carry data-min and data-max attributes so the raw value
// (e.g. 7 on a 1–10 scale) is normalised to 0–100 before being fed into
// the weighted sum, exactly as the backend extract_score helper does.
export default class extends Controller {
  static targets = ["attributeInput", "overallBar", "overallValue", "formulaText", "valueDisplay"]
  static values = {
    weights: Object,  // { subcheckpoint_uuid: weight_float, ... }
    caps: Array        // [subcheckpoint_uuid, ...]
  }

  connect() {
    this.recalculate()
  }

  recalculate() {
    const scores = {} // normalised 0–100 scores keyed by subcheckpoint id

    this.attributeInputTargets.forEach(input => {
      const id = input.dataset.subcheckpointId
      const raw = parseFloat(input.value) || 0

      if (input.type === "radio" && !input.checked) return

      // Normalise to 0-100
      if (input.dataset.scoringType === "Number") {
        const min = parseFloat(input.min) || 0
        const max = parseFloat(input.max) || 100
        const range = max - min
        scores[id] = range > 0 ? ((raw - min) / range * 100) : 0
      } else {
        scores[id] = raw // Percentage & Multiple Choice are already 0-100
      }

      // Update the value display next to sliders
      if (input.type === "range") {
        this.valueDisplayTargets.forEach(display => {
          if (display.dataset.subcheckpointId === id) {
            display.textContent = `${Math.round(raw)}%`
          }
        })
      }
    })

    // Weighted sum
    let weightedSum = 0
    const formulaParts = []
    for (const [id, weight] of Object.entries(this.weightsValue)) {
      const score = scores[id] || 0
      weightedSum += score * weight
      formulaParts.push(`(${Math.round(score)}\u00d7${weight})`)
    }

    // Cap
    let capApplied = false
    let capValue = Infinity
    let capName = ""
    const capsArray = this.capsValue || []
    capsArray.forEach(id => {
      const score = scores[id] || 0
      if (score < capValue) {
        capValue = score
        const input = this.attributeInputTargets.find(i => i.dataset.subcheckpointId === id)
        capName = input ? input.dataset.attributeName : ""
      }
    })

    if (capsArray.length === 0) capValue = Infinity

    const overall = capsArray.length > 0 ? Math.min(weightedSum, capValue) : weightedSum
    capApplied = (capsArray.length > 0 && capValue < weightedSum)

    // Update overall bar
    if (this.hasOverallBarTarget) {
      this.overallBarTarget.style.width = `${Math.min(Math.max(overall, 0), 100)}%`
    }
    if (this.hasOverallValueTarget) {
      this.overallValueTarget.textContent = `${overall.toFixed(1)}%`
    }

    // Update formula text
    if (this.hasFormulaTextTarget) {
      let text = `weighted_sum = ${formulaParts.join("+")} = ${weightedSum.toFixed(1)}`
      if (capsArray.length > 0) {
        text += ` | Cap (${capName}) = ${Math.round(capValue)}`
        text += ` | Overall = MIN(${weightedSum.toFixed(1)}, ${Math.round(capValue)}) = ${overall.toFixed(1)}%`
      } else {
        text += ` | Overall = ${overall.toFixed(1)}%`
      }
      this.formulaTextTarget.textContent = text
    }
  }
}
