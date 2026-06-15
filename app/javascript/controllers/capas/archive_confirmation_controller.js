import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["message", "title", "confirmButton"]
  
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
      
      // Update title and button text based on intent (archive/unarchive) with translations
      const intent = options.intent || (message && message.toLowerCase().includes('unarchive') ? 'unarchive' : 'archive')
      const archiveTitle = this.element.dataset.archiveTitle || 'Archive CAPA'
      const archiveButton = this.element.dataset.archiveButton || 'Archive'
      const unarchiveTitle = this.element.dataset.unarchiveTitle || archiveTitle
      const unarchiveButton = this.element.dataset.unarchiveButton || archiveButton

      if (this.hasTitleTarget) {
        this.titleTarget.textContent = intent === 'unarchive' ? unarchiveTitle : archiveTitle
      }
      if (this.hasConfirmButtonTarget) {
        this.confirmButtonTarget.textContent = intent === 'unarchive' ? unarchiveButton : archiveButton
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


