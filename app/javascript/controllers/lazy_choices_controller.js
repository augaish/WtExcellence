import { Controller } from "@hotwired/stimulus"

// Turns a plain select into the searchable picker the first time its
// <details> opens. A page with hundreds of pickers stays quick to load.
export default class extends Controller {
  static targets = ["picker"]

  opened() {
    if (!this.element.open || this.done) return
    this.done = true
    this.pickerTargets.forEach((wrapper) => {
      wrapper.setAttribute("data-controller", "choices-select")
    })
  }
}
