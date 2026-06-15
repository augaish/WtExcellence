import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["message"]
  
  connect() {
    this.pendingResolve = null
  }

  // Public method to show modal and return Promise
  async confirm(message, options = {}) {
    return new Promise((resolve) => {
      this.pendingResolve = resolve
      
      // Update message
      if (this.hasMessageTarget) {
        this.messageTarget.textContent = message
      }
      
      // Show modal
      this.element.showModal()
    })
  }

  confirmAction() {
    if (this.pendingResolve) {
      this.pendingResolve(true)
      this.pendingResolve = null
    }
    this.element.close()
  }

  cancelAction() {
    if (this.pendingResolve) {
      this.pendingResolve(false)
      this.pendingResolve = null
    }
    this.element.close()
  }

  close() {
    this.cancelAction()
  }
}

