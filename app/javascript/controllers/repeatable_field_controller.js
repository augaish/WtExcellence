import { Controller } from "@hotwired/stimulus"

// A "+ add" list of identical inputs (used for org unit mandates).
// Always leaves at least one empty row so the field never disappears entirely.
export default class extends Controller {
  static targets = ["list", "row", "template"]

  add() {
    const fragment = this.templateTarget.content.cloneNode(true)
    this.listTarget.appendChild(fragment)
    const inputs = this.listTarget.querySelectorAll("input[type='text']")
    const last = inputs[inputs.length - 1]
    if (last) last.focus()
  }

  remove(event) {
    const row = event.currentTarget.closest("[data-repeatable-field-target='row']")
    if (!row) return

    row.remove()
    if (this.listTarget.children.length === 0) this.add()
  }
}
