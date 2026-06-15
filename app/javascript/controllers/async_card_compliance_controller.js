import { Controller } from "@hotwired/stimulus"

// Fetches per-standard compliance for the standards index cards after the
// page renders. The ERB renders each card's compliance block with a spinner;
// on connect we hit /standards/compliance once with the list of visible ids
// and fill every card's value/bar/subtext/tool-breakdown together.
export default class extends Controller {
  static targets = ["block"]
  static values = { url: String }

  connect() {
    if (!this.urlValue || this.blockTargets.length === 0) return
    this.fetchData()
  }

  async fetchData() {
    const ids = this.blockTargets.map((b) => b.dataset.standardId).filter(Boolean)
    if (ids.length === 0) return

    const params = new URLSearchParams()
    ids.forEach((id) => params.append("ids[]", id))

    try {
      const response = await fetch(`${this.urlValue}?${params.toString()}`, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json()
      const compliance = data.compliance || {}
      this.blockTargets.forEach((block) => {
        const id = block.dataset.standardId
        const row = compliance[id] || {}
        this.populate(block, row)
      })
    } catch (err) {
      console.error("async-card-compliance fetch failed:", err)
      this.blockTargets.forEach((block) => this.populate(block, { compliance_percentage: 0 }))
    }
  }

  populate(block, row) {
    const pct = Number(row.compliance_percentage ?? row.average_company_compliance ?? 0)
    const pctDisplay = Number.isFinite(pct) ? pct.toFixed(2) : "0.00"

    const valueEl = block.querySelector('[data-role="value"]')
    if (valueEl) {
      valueEl.innerHTML = `${pctDisplay}%`
    }

    const barEl = block.querySelector('[data-role="bar"]')
    if (barEl) {
      barEl.style.width = `${Math.max(0, Math.min(100, pct))}%`
    }

    // Super-admin cards already render a static subtext server-side ("Across N
    // companies"). For regular users we only replace the subtext when the
    // compliance is 0 to show the "No Evaluations" hint.
    const subtextEl = block.querySelector('[data-role="subtext"]')
    const hasStaticSubtext = subtextEl && subtextEl.textContent.trim().length > 0
    if (subtextEl && !hasStaticSubtext) {
      if (pct === 0) {
        subtextEl.textContent = "No Evaluations"
        subtextEl.classList.remove("hidden")
      } else {
        subtextEl.classList.add("hidden")
      }
    }

    const tools = Array.isArray(row.tool_compliance_data) ? row.tool_compliance_data : []
    const toolBreakdown = block.querySelector('[data-role="tool-breakdown"]')
    const toolList = block.querySelector('[data-role="tool-breakdown-list"]')
    if (toolBreakdown && toolList && tools.length > 1) {
      toolList.innerHTML = tools
        .map((t) => {
          const name = this.escapeHtml(t.tool_name || "")
          const v = Number(t.compliance_percentage || 0).toFixed(2)
          return `
            <div class="flex items-center justify-between text-xs">
              <span class="text-gray-600">${name}</span>
              <span class="font-semibold text-[#5C3984]">${v}%</span>
            </div>`
        })
        .join("")
      toolBreakdown.classList.remove("hidden")
    } else if (toolBreakdown) {
      toolBreakdown.classList.add("hidden")
    }
  }

  escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }
}
