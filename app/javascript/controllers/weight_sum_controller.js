import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["banner", "message"]

  connect() {
    // Initial calculation after a short delay (wait for DOM)
    setTimeout(() => this.recalculate(), 200)
  }

  recalculate() {
    // Find all visible weight inputs (skip destroyed ones)
    const weightInputs = document.querySelectorAll('input[name*="[weight]"]:not([name*="_destroy"])')
    const weights = []
    let hasAny = false

    weightInputs.forEach(input => {
      // Skip if inside a destroyed wrapper
      const wrapper = input.closest("[data-nested-form-wrapper]")
      if (wrapper) {
        const destroyInput = wrapper.querySelector('input[name*="_destroy"]')
        if (destroyInput && destroyInput.value === "1") return
      }
      // Only count subcheckpoint-level weights (exclude checkpoint-level and
      // nested multiple-choice option weights).
      if (!input.name.includes("subcheckpoints_attributes")) return
      if (input.name.includes("multiple_choice_options_attributes")) return

      const val = parseFloat(input.value)
      if (!isNaN(val) && val > 0) {
        weights.push(val)
        hasAny = true
      }
    })

    if (!hasAny) {
      // All null/empty — equal weight fallback will apply
      this.showInfo("No weights configured. Equal weighting will be applied automatically.")
      return
    }

    const sum = weights.reduce((a, b) => a + b, 0)

    if (Math.abs(sum - 100) < 0.01) {
      this.hide()
    } else {
      const display = Number.isInteger(sum) ? sum.toString() : sum.toFixed(2).replace(/\.?0+$/, "")
      this.showWarning(`Weights sum to ${display}% (should be 100%). Saving is still allowed.`)
    }
  }

  showWarning(msg) {
    if (!this.hasBannerTarget) return
    this.bannerTarget.classList.remove("hidden", "bg-blue-50", "border-blue-200", "text-blue-800")
    this.bannerTarget.classList.add("bg-amber-50", "border-amber-200", "text-amber-800")
    this.messageTarget.textContent = msg
  }

  showInfo(msg) {
    if (!this.hasBannerTarget) return
    this.bannerTarget.classList.remove("hidden", "bg-amber-50", "border-amber-200", "text-amber-800")
    this.bannerTarget.classList.add("bg-blue-50", "border-blue-200", "text-blue-800")
    this.messageTarget.textContent = msg
  }

  hide() {
    if (!this.hasBannerTarget) return
    this.bannerTarget.classList.add("hidden")
  }
}
