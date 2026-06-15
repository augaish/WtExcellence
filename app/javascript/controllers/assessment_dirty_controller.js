import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["saveDraft"]

  connect() {
    this.dirty = false
    this.handleDirty = () => this.markDirty()
    document.addEventListener("assessment:dirty", this.handleDirty)
  }

  disconnect() {
    document.removeEventListener("assessment:dirty", this.handleDirty)
  }

  markDirty() {
    if (this.dirty) return
    this.dirty = true

    if (this.hasSaveDraftTarget) {
      const btn = this.saveDraftTarget
      btn.classList.remove("text-[#797C81]", "border-gray-300", "hover:bg-gray-50")
      btn.classList.add("text-white", "bg-[#5C3984]", "hover:bg-[#4A2F6B]", "border-[#5C3984]")
    }
  }

  // Called from any form input/change
  changed() {
    document.dispatchEvent(new CustomEvent("assessment:dirty"))
  }
}
