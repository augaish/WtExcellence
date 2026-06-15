import { Controller } from "@hotwired/stimulus"

/**
 * Confirm link controller: shows the dashboard confirmation modal, then submits the request on confirm.
 * Use on buttons/links that should ask "Are you sure?" before performing a destructive action.
 *
 * data-controller="confirm-link"
 * data-confirm-link-message-value="Are you sure you want to delete?"
 * data-confirm-link-url-value="/dashboard/..."
 * data-confirm-link-method-value="delete"
 * data-confirm-link-title-value="Confirm Delete"
 * data-confirm-link-confirm-text-value="Delete"
 * data-confirm-link-button-style-value="danger"
 */
export default class extends Controller {
  static values = {
    message: String,
    url: String,
    method: { type: String, default: "delete" },
    title: String,
    confirmText: String,
    buttonStyle: { type: String, default: "danger" }
  }

  async handleClick(event) {
    event.preventDefault()
    if (!this.messageValue || !this.urlValue) {
      console.warn("confirm-link: message and url are required")
      return
    }

    const showModal = window.showDashboardConfirmationModal
    if (!showModal) {
      if (confirm(this.messageValue)) {
        this.submit()
      }
      return
    }

    const options = {
      title: this.titleValue || undefined,
      confirmText: this.confirmTextValue || undefined,
      buttonStyle: this.buttonStyleValue || "danger"
    }
    const confirmed = await showModal(this.messageValue, options)
    if (confirmed) {
      this.submit()
    }
  }

  submit() {
    const url = this.urlValue
    const method = (this.methodValue || "delete").toLowerCase()
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (!csrfToken) {
      window.location.href = url
      return
    }

    const form = document.createElement("form")
    form.method = "post"
    form.action = url
    form.style.display = "none"

    const methodInput = document.createElement("input")
    methodInput.name = "_method"
    methodInput.value = method === "get" ? "get" : method
    form.appendChild(methodInput)

    const csrfInput = document.createElement("input")
    csrfInput.name = "authenticity_token"
    csrfInput.value = csrfToken
    form.appendChild(csrfInput)

    document.body.appendChild(form)
    form.requestSubmit()
  }
}
