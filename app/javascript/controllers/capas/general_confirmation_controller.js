import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["message", "title", "confirmButton"]
  
  connect() {
    this.pendingResolve = null
  }

  // Public method to show modal and return Promise
  // Options: { title, message, confirmText, buttonStyle }
  // buttonStyle: 'danger' (red), 'primary' (purple), 'default' (gray)
  async confirm(message, options = {}) {
    return new Promise((resolve) => {
      this.pendingResolve = resolve
      
      // Update message
      if (this.hasMessageTarget) {
        this.messageTarget.textContent = message
      }
      
      // Update title
      if (this.hasTitleTarget) {
        this.titleTarget.textContent = options.title || 'Confirm Action'
      }
      
      // Update confirm button text and style
      if (this.hasConfirmButtonTarget) {
        this.confirmButtonTarget.textContent = options.confirmText || 'Confirm'
        
        // Remove existing style classes
        this.confirmButtonTarget.classList.remove(
          'bg-[#EA4034]', 'hover:bg-[#D32F2F]', // danger
          'bg-[#5C3984]', 'hover:bg-[#4A2F6B]', // primary
          'bg-gray-600', 'hover:bg-gray-700'     // default
        )
        
        // Apply new style based on buttonStyle option
        const buttonStyle = options.buttonStyle || 'danger'
        switch(buttonStyle) {
          case 'danger':
            this.confirmButtonTarget.classList.add('bg-[#EA4034]', 'hover:bg-[#D32F2F]')
            break
          case 'primary':
            this.confirmButtonTarget.classList.add('bg-[#5C3984]', 'hover:bg-[#4A2F6B]')
            break
          case 'default':
            this.confirmButtonTarget.classList.add('bg-gray-600', 'hover:bg-gray-700')
            break
          default:
            this.confirmButtonTarget.classList.add('bg-[#EA4034]', 'hover:bg-[#D32F2F]')
        }
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

