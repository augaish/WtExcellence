import { Controller } from "@hotwired/stimulus"

// The other party of an agreement is either one of our units (pick it) or a
// name (type it). The form shows the field that fits the chosen kind.
export default class extends Controller {
  static targets = ["kind", "unitBox", "nameBox"]

  connect() { this.refresh() }

  refresh() {
    if (!this.hasKindTarget) return
    const internal = this.kindTarget.value === "internal_unit"
    if (this.hasUnitBoxTarget) this.unitBoxTarget.hidden = !internal
    if (this.hasNameBoxTarget) this.nameBoxTarget.hidden = internal
  }
}
