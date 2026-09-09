import { Controller } from "@hotwired/stimulus"

// Shows or hides the element whose id is given, and says so on the button.
export default class extends Controller {
  static values = { id: String }

  toggle() {
    const target = document.getElementById(this.idValue)
    if (!target) return
    target.hidden = !target.hidden
    this.element.setAttribute("aria-expanded", String(!target.hidden))
  }
}
