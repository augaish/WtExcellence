import { Controller } from "@hotwired/stimulus"

/**
 * General Confirmation Modal Controller
 * 
 * A reusable modal for confirmations. Returns a Promise that resolves to true/false.
 * 
 * Usage:
 *   const modal = document.getElementById('generalConfirmationModal');
 *   const controller = this.application.getControllerForElementAndIdentifier(
 *     modal, 'general-confirmation'
 *   );
 *   const confirmed = await controller.confirm('Are you sure?', {
 *     title: 'Confirm Delete',
 *     confirmText: 'Delete',
 *     buttonStyle: 'danger' // 'danger', 'primary', or 'default'
 *   });
 *   if (confirmed) {
 *     // User confirmed
 *   }
 */
export default class extends Controller {
  static targets = ["message", "title", "confirmButton"]
  
  connect() {
    this.pendingResolve = null
  }

  // Public method to show modal and return Promise
  // Options: { title, message, confirmText, buttonStyle }
  // buttonStyle: 'danger' (red), 'primary' (purple), 'default' (gray)
  async confirm(message, options = {}) {
    this.pendingOptions = options
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
      
      // Update confirm button text and style (reset state so reused modal works)
      if (this.hasConfirmButtonTarget) {
        const btn = this.confirmButtonTarget
        btn.disabled = false
        btn.textContent = options.confirmText || 'Confirm'
        
        // Remove existing style classes
        btn.classList.remove(
          'bg-[#EA4034]', 'hover:bg-[#D32F2F]', // danger
          'bg-[#5C3984]', 'hover:bg-[#4A2F6B]', // primary
          'bg-gray-600', 'hover:bg-gray-700'     // default
        )
        
        // Apply new style based on buttonStyle option
        const buttonStyle = options.buttonStyle || 'danger'
        switch(buttonStyle) {
          case 'danger':
            btn.classList.add('bg-[#EA4034]', 'hover:bg-[#D32F2F]')
            break
          case 'primary':
            btn.classList.add('bg-[#5C3984]', 'hover:bg-[#4A2F6B]')
            break
          case 'default':
            btn.classList.add('bg-gray-600', 'hover:bg-gray-700')
            break
          default:
            btn.classList.add('bg-[#EA4034]', 'hover:bg-[#D32F2F]')
        }
      }
      
      // Show modal
      this.element.showModal()
    })
  }

  async confirmAction() {
    const options = this.pendingOptions || {}
    if (typeof options.asyncConfirm === "function") {
      const btn = this.hasConfirmButtonTarget ? this.confirmButtonTarget : null
      if (btn) {
        const originalContent = btn.innerHTML
        const loadingText = options.loadingText || "Loading..."
        btn.disabled = true
        btn.innerHTML = `<span class="inline-flex items-center gap-2"><svg class="w-4 h-4 animate-spin flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" /></svg><span>${loadingText}</span></span>`
        try {
          await options.asyncConfirm(btn)
          if (this.pendingResolve) {
            this.pendingResolve(true)
            this.pendingResolve = null
          }
          this.pendingOptions = null
          this.element.close()
        } catch (err) {
          btn.disabled = false
          btn.innerHTML = originalContent
          if (this.pendingResolve) {
            this.pendingResolve(false)
            this.pendingResolve = null
          }
          this.pendingOptions = null
          // Keep modal open so user can try again or cancel
        }
      } else {
        try {
          await options.asyncConfirm(null)
          if (this.pendingResolve) {
            this.pendingResolve(true)
            this.pendingResolve = null
          }
          this.pendingOptions = null
          this.element.close()
        } catch (err) {
          if (this.pendingResolve) {
            this.pendingResolve(false)
            this.pendingResolve = null
          }
          this.pendingOptions = null
        }
      }
      return
    }
    if (this.pendingResolve) {
      this.pendingResolve(true)
      this.pendingResolve = null
    }
    this.pendingOptions = null
    this.element.close()
  }

  cancelAction() {
    if (this.pendingResolve) {
      this.pendingResolve(false)
      this.pendingResolve = null
    }
    this.pendingOptions = null
    this.element.close()
  }

  close() {
    this.cancelAction()
  }
}

