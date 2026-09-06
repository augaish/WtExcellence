import { Controller } from "@hotwired/stimulus"

// Shows a dependent field only when the trigger select says "true"
// (used for "intersecting units", which only applies when there ARE
// intersections).
export default class extends Controller {
  static targets = ["trigger", "dependent"]

  connect() {
    this.toggle()
  }

  toggle() {
    if (!this.hasTriggerTarget) return
    const on = this.triggerTarget.value === "true"
    this.dependentTargets.forEach((el) => { el.hidden = !on })
  }
}
