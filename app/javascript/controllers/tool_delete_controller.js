import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    toolId: String,
    toolName: String
  }

  async delete(event) {
    event.preventDefault()
    event.stopPropagation()

    // Get the modal element and its controller
    const modal = document.getElementById('generalConfirmationModal')
    if (!modal) {
      console.error('General confirmation modal not found')
      return
    }

    const modalController = this.application.getControllerForElementAndIdentifier(
      modal,
      'general-confirmation'
    )

    if (!modalController) {
      console.error('General confirmation controller not found')
      return
    }

    // Show confirmation modal
    const confirmed = await modalController.confirm(
      `Are you sure you want to delete '${this.toolNameValue}'? This action cannot be undone.`,
      {
        title: 'Delete Tool',
        confirmText: 'Delete',
        buttonStyle: 'danger'
      }
    )

    if (confirmed) {
      // Create a form and submit it
      const form = document.createElement('form')
      form.method = 'POST'
      form.action = `/tools/${this.toolIdValue}`
      
      // Add CSRF token
      const csrfToken = document.querySelector('meta[name="csrf-token"]')
      if (csrfToken) {
        const input = document.createElement('input')
        input.type = 'hidden'
        input.name = 'authenticity_token'
        input.value = csrfToken.content
        form.appendChild(input)
      }

      // Add method override for DELETE
      const methodInput = document.createElement('input')
      methodInput.type = 'hidden'
      methodInput.name = '_method'
      methodInput.value = 'delete'
      form.appendChild(methodInput)

      // Submit the form
      document.body.appendChild(form)
      form.submit()
    }
  }
}

