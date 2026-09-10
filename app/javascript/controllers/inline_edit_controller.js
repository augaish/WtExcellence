import { Controller } from "@hotwired/stimulus"

// A pencil that turns a line of text into its own edit form, in place. Clicking
// outside the form or pressing Escape closes it without saving; Save submits.
//
//   <div data-controller="inline-edit">
//     <span data-inline-edit-target="text">…</span>
//     <button data-action="click->inline-edit#open">✎</button>
//     <form hidden data-inline-edit-target="form">…</form>
//   </div>
export default class extends Controller {
  static targets = ["text", "form"]

  connect() {
    this.onDocumentClick = (event) => {
      if (this.formTarget.hidden || this.element.contains(event.target)) return
      this.close()
    }
    this.onKeydown = (event) => { if (event.key === "Escape" && !this.formTarget.hidden) this.close() }
  }

  disconnect() { this.close() }

  open(event) {
    event.preventDefault()
    this.textTargets.forEach((t) => { t.hidden = true })
    this.formTarget.hidden = false
    this.formTarget.querySelector("input, textarea")?.focus()
    document.addEventListener("click", this.onDocumentClick)
    document.addEventListener("keydown", this.onKeydown)
  }

  close() {
    if (!this.hasFormTarget) return
    this.formTarget.hidden = true
    this.textTargets.forEach((t) => { t.hidden = false })
    document.removeEventListener("click", this.onDocumentClick)
    document.removeEventListener("keydown", this.onKeydown)
  }
}
