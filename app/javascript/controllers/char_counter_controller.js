import { Controller } from "@hotwired/stimulus"

// Live character counter for text fields with maxlength.
// Usage: data-controller="char-counter" on the wrapper div,
//        data-char-counter-target="input" on the textarea,
//        data-char-counter-target="counter" on the counter display span.
export default class extends Controller {
  static targets = ["input", "counter"]
  static values = { max: { type: Number, default: 100 } }

  connect() {
    this.update()
  }

  update() {
    if (!this.hasInputTarget || !this.hasCounterTarget) return
    const len = this.inputTarget.value.length
    this.counterTarget.textContent = `${len}/${this.maxValue}`
  }
}
