import { Controller } from "@hotwired/stimulus"

// Appends the chosen option's value to a text field: used to drop an approved
// glossary definition into a clause as it is written.
export default class extends Controller {
  static targets = ["field"]

  insert(event) {
    const value = event.target.value
    if (!value || !this.hasFieldTarget) return
    const field = this.fieldTarget
    field.value = (field.value ? field.value.trimEnd() + "\n" : "") + value
    field.dispatchEvent(new Event("input", { bubbles: true }))
    event.target.value = ""
    field.focus()
  }
}
