import { Controller } from "@hotwired/stimulus"

// Shows full text in a custom tooltip on hover for truncated content.
// Usage: wrap the truncated element and set the value:
//   <div data-controller="truncate-tooltip" data-truncate-tooltip-text-value="Full text here">
//     <span class="truncate ...">Short text</span>
//   </div>
export default class extends Controller {

  static values = { text: String, delay: { type: Number, default: 200 } }

  connect() {
    this.showBound = this.show.bind(this)
    this.hideBound = this.hide.bind(this)
    this.element.addEventListener("mouseenter", this.showBound)
    this.element.addEventListener("mouseleave", this.hideBound)
  }

  disconnect() {
    this.element.removeEventListener("mouseenter", this.showBound)
    this.element.removeEventListener("mouseleave", this.hideBound)
    if (this._showTimeout) clearTimeout(this._showTimeout)
    this.hide()
  }

  show() {
    if (this._showTimeout) clearTimeout(this._showTimeout)
    this._showTimeout = setTimeout(() => this._doShow(), this.delayValue)
  }

  hide() {
    if (this._showTimeout) {
      clearTimeout(this._showTimeout)
      this._showTimeout = null
    }
    if (this._tooltip && this._tooltip.parentNode) {
      this._tooltip.parentNode.removeChild(this._tooltip)
      this._tooltip = null
    }
  }

  _doShow() {
    this._showTimeout = null
    const text = this.textValue
    if (!text || text.trim() === "") return

    this.hide()
    this._tooltip = document.createElement("div")
    this._tooltip.setAttribute("role", "tooltip")
    this._tooltip.className = "truncate-tooltip-popover"
    this._tooltip.textContent = text
    document.body.appendChild(this._tooltip)

    const rect = this.element.getBoundingClientRect()
    const tipRect = this._tooltip.getBoundingClientRect()
    const padding = 8
    let top = rect.top - tipRect.height - padding
    const left = Math.max(padding, Math.min(rect.left, window.innerWidth - tipRect.width - padding))

    if (top < padding) {
      top = rect.bottom + padding
    }
    this._tooltip.style.position = "fixed"
    this._tooltip.style.left = `${left}px`
    this._tooltip.style.top = `${top}px`
    this._tooltip.style.zIndex = "9999"
  }
}
