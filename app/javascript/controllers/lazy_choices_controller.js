import { Controller } from "@hotwired/stimulus"

// Turns a plain select into the searchable picker the first time it is shown:
// when its <details> opens, or when a hidden panel it sits in is revealed. A
// page with hundreds of pickers stays quick to load, and a picker built while
// hidden never comes up as a plain list.
export default class extends Controller {
  static targets = ["picker"]

  connect() {
    this.observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) this.build()
    })
    this.observer.observe(this.element)
  }

  disconnect() { this.observer?.disconnect() }

  opened() {
    if (this.element.open) this.build()
  }

  build() {
    if (this.done) return
    this.done = true
    this.observer?.disconnect()
    const wrappers = this.pickerTargets.length ? this.pickerTargets : [this.element]
    wrappers.forEach((wrapper) => wrapper.setAttribute("data-controller", "choices-select"))
  }
}
