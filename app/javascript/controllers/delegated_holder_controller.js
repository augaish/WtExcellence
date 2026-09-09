import { Controller } from "@hotwired/stimulus"

// A delegated holder chip. Pressing the swap shows who originally held the
// authority; pressing again, or a minute passing, shows the delegate again.
// Only this reader's screen changes; nothing is saved.
export default class extends Controller {
  static targets = ["label"]
  static values = { original: String, delegate: String }

  swap() {
    if (this.showingOriginal) return this.showDelegate()
    this.showingOriginal = true
    this.labelTarget.textContent = this.originalValue
    this.labelTarget.classList.replace("bg-amber-100", "bg-[#F6EEFF]")
    this.timer = setTimeout(() => this.showDelegate(), 60_000)
  }

  showDelegate() {
    clearTimeout(this.timer)
    this.showingOriginal = false
    this.labelTarget.textContent = this.delegateValue
    this.labelTarget.classList.replace("bg-[#F6EEFF]", "bg-amber-100")
  }

  disconnect() { clearTimeout(this.timer) }
}
