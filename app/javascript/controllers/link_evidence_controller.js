import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="link-evidence"
// Links an existing library document to a Standard (or other attachable) by
// POSTing JSON to EvidenceAttachmentsController#create, which expects
// { upload_id, items: [{ type, id }] }.
export default class extends Controller {
  static targets = ["submit", "radio"]
  static values = {
    url: String,
    attachableType: String,
    attachableId: String
  }

  select() {
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = !this.selectedUploadId()
    }
  }

  selectedUploadId() {
    const checked = this.radioTargets.find((r) => r.checked)
    return checked ? checked.value : null
  }

  async submit(event) {
    event.preventDefault()
    const uploadId = this.selectedUploadId()
    if (!uploadId) return

    this.submitTarget.disabled = true
    const originalText = this.submitTarget.textContent
    this.submitTarget.textContent = "..."

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]').content
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        body: JSON.stringify({
          upload_id: uploadId,
          items: [{ type: this.attachableTypeValue, id: this.attachableIdValue }]
        })
      })
      const data = await response.json()

      if (data.success && data.created_count > 0) {
        window.location.reload()
      } else {
        const message = (data.errors && data.errors.join(", ")) || data.error || "Could not link the document."
        window.alert(message)
        this.submitTarget.disabled = false
        this.submitTarget.textContent = originalText
      }
    } catch (error) {
      window.alert("Something went wrong. Please try again.")
      this.submitTarget.disabled = false
      this.submitTarget.textContent = originalText
    }
  }
}
