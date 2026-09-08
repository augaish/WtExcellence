import { Controller } from "@hotwired/stimulus"

// Offers only the units that suit the chosen commitment, so a percentage
// cannot be entered in hours. The server still refuses a mismatch; this stops
// the form inviting one.
export default class extends Controller {
  static targets = ["metric", "unit"]

  connect() { this.refresh() }

  refresh() {
    const units = JSON.parse(this.unitTarget.dataset.units || "{}")
    const labels = JSON.parse(this.unitTarget.dataset.labels || "{}")
    const allowed = units[this.metricTarget.value] || []

    this.unitTarget.innerHTML = ""
    this.unitTarget.appendChild(new Option("", ""))
    allowed.forEach((unit) => this.unitTarget.appendChild(new Option(labels[unit] || unit, unit)))
  }
}
