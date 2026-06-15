import { Controller } from "@hotwired/stimulus"

// Fetches a single numeric metric from a JSON endpoint after the page renders
// and swaps a spinner for the returned value. Used by the overview page for
// metrics expensive enough to block initial render.
//
// Usage:
//   <div data-controller="async-metric"
//        data-async-metric-url-value="/foo.json"
//        data-async-metric-key-value="avg_compliance"
//        data-async-metric-suffix-value="%">
//     <span data-async-metric-target="value"> (spinner) </span>
//   </div>
export default class extends Controller {
  static targets = ["value"]
  static values = {
    url: String,
    key: String,
    suffix: { type: String, default: "" },
    prefix: { type: String, default: "" }
  }

  connect() {
    if (!this.urlValue || !this.hasValueTarget) return
    this.fetchMetric()
  }

  async fetchMetric() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json()
      const value = this.keyValue ? data[this.keyValue] : data
      this.valueTarget.textContent = `${this.prefixValue}${value}${this.suffixValue}`
    } catch (err) {
      console.error("async-metric fetch failed:", err)
      this.valueTarget.textContent = "—"
    }
  }
}
