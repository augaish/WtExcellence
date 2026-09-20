import { Controller } from "@hotwired/stimulus"

// The add-element form shows only the fields that mean something for the
// chosen type: an event has no inputs, outputs or description; only a gateway
// has outcomes. Each field names the kinds it belongs to in data-show-for.
export default class extends Controller {
  static targets = ["type", "field"]

  static EVENTS = ["startEvent", "endEvent"]
  static ARTIFACTS = ["dataObject", "dataStore", "message", "textAnnotation"]

  connect() { this.toggle() }

  kindOf(type) {
    if (this.constructor.EVENTS.includes(type)) return "event"
    if (this.constructor.ARTIFACTS.includes(type)) return "artifact"
    if (type === "gateway") return "gateway"
    return "task"
  }

  toggle() {
    if (!this.hasTypeTarget) return
    const kind = this.kindOf(this.typeTarget.value)
    this.fieldTargets.forEach((field) => {
      const shown = (field.dataset.showFor || "").split(" ").includes(kind)
      field.hidden = !shown
      field.querySelectorAll("input, textarea, select").forEach((input) => { if (!shown) input.value = "" })
    })
  }
}
