import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    checklistItemId: String,
    toolCheckpointId: String
  }

  connect() {
    this.timeout = null
    this.lastSaved = this.element.value
  }

  save() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.persist(), 1000)

    // Mark page as dirty
    document.dispatchEvent(new CustomEvent("assessment:dirty"))
  }

  async persist() {
    const value = this.element.value
    if (value === this.lastSaved) return

    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('[name="csrf-token"]')?.content
        },
        body: JSON.stringify({
          checklist_item_id: this.checklistItemIdValue,
          tool_checkpoint_id: this.toolCheckpointIdValue,
          summary: value
        })
      })

      if (response.ok) {
        this.lastSaved = value
      }
    } catch (e) {
      // Silent fail — user can still save via Save Draft
    }
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
