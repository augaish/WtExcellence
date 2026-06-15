import { Controller } from "@hotwired/stimulus"

// Fetches per-standard compliance % for the overview "Average Compliance by
// Standard" table after initial render. Each row's compliance cell starts
// with a spinner; once the response lands, the cell is replaced with the
// progress bar + value.
export default class extends Controller {
  static targets = ["cell"]
  static values = { url: String }

  connect() {
    if (!this.urlValue) return
    this.fetchData()
  }

  async fetchData() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json()
      const compliance = data.compliance || {}
      this.cellTargets.forEach((cell) => {
        const row = cell.closest("tr")
        const id = row?.dataset?.standardId
        const value = id && Object.prototype.hasOwnProperty.call(compliance, id)
          ? Number(compliance[id]).toFixed(1).replace(/\.0$/, "")
          : "0"
        cell.innerHTML = this.renderBar(value)
      })
    } catch (err) {
      console.error("async-standards-compliance fetch failed:", err)
      this.cellTargets.forEach((cell) => {
        cell.innerHTML = '<span class="text-sm text-[#797C81]">—</span>'
      })
    }
  }

  renderBar(value) {
    const pct = Math.max(0, Math.min(100, Number(value)))
    return `
      <div class="flex items-center gap-2">
        <div class="flex-1 bg-[#E3E3E3] rounded-full h-2">
          <div class="bg-[#5C3984] h-2 rounded-full" style="width: ${pct}%"></div>
        </div>
        <span class="text-sm text-[#0D1120] font-medium w-12 text-end">${pct}%</span>
      </div>`
  }
}
