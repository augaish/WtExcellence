import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["notification"]

  connect() {
    // Clear any existing timeouts from previous page loads
    this.clearAllTimeouts()
    
    // Clean up any stale notifications that might have been restored from browser history
    // Only process notifications that haven't been processed yet
    this.notificationTargets.forEach(notification => {
      // Skip if already processed (has auto-dismiss setup)
      if (notification.dataset.autoDismissSetup) {
        // This notification was restored from history, clear it immediately
        notification.remove()
        return
      }
      
      this.addEnterAnimation(notification)
      this.setupAutoDismiss(notification)
    })

    this.boundShowNotification = this.showNotification.bind(this)
    document.addEventListener('toast:show', this.boundShowNotification)
    
    // Listen for Turbo navigation to clean up on page transitions
    this.boundBeforeVisit = this.handleBeforeVisit.bind(this)
    document.addEventListener('turbo:before-visit', this.boundBeforeVisit)
  }

  disconnect() {
    document.removeEventListener('toast:show', this.boundShowNotification)
    document.removeEventListener('turbo:before-visit', this.boundBeforeVisit)
    
    this.clearAllTimeouts()
  }

  handleBeforeVisit() {
    // Clear all notifications and timeouts before navigation
    this.clearAllTimeouts()
    this.dismissAll()
  }

  clearAllTimeouts() {
    this.notificationTargets.forEach(notification => {
      if (notification.dataset.dismissTimeout) {
        clearTimeout(parseInt(notification.dataset.dismissTimeout))
        delete notification.dataset.dismissTimeout
      }
      delete notification.dataset.autoDismissSetup
    })
  }

  showNotification(event) {
    const { notificationHtml } = event.detail
    if (!notificationHtml) return

    // Find or ensure toast container exists
    let toastContainer = document.querySelector('[data-controller="toast"]')
    if (!toastContainer) {
      // Create toast container if it doesn't exist (shouldn't happen, but safety check)
      toastContainer = document.createElement('div')
      toastContainer.setAttribute('data-controller', 'toast')
      toastContainer.className = 'fixed top-4 right-4 z-50 space-y-3 w-96'
      document.body.appendChild(toastContainer)
      
      // Trigger Stimulus to connect to the new element
      // Stimulus should auto-detect via MutationObserver, but we can manually trigger if needed
      const application = this.application
      if (application) {
        // Stimulus will auto-connect via MutationObserver
        // But ensure it's connected by accessing the controller
        setTimeout(() => {
          const controller = application.getControllerForElementAndIdentifier(toastContainer, 'toast')
          if (controller && !controller.boundShowNotification) {
            controller.connect()
          }
        }, 0)
      }
    }

    const temp = document.createElement('div')
    temp.innerHTML = notificationHtml.trim()
    const notification = temp.firstElementChild

    if (!notification) return

    // Append to the container (either existing or this.element)
    const container = toastContainer || this.element
    if (!container) return
    
    container.appendChild(notification)

    // Get the controller instance for the container
    const application = this.application
    let controller = this
    if (toastContainer && toastContainer !== this.element) {
      try {
        controller = application.getControllerForElementAndIdentifier(toastContainer, 'toast') || this
      } catch (e) {
        // Fallback to this controller
        controller = this
      }
    }

    controller.addEnterAnimation(notification)
    controller.setupAutoDismiss(notification)
  }

  setupAutoDismiss(notification) {
    if (notification.dataset.autoDismissSetup) return
    notification.dataset.autoDismissSetup = 'true'
    
    const timeout = setTimeout(() => {
      this.dismiss(notification)
    }, 5000)
    
    notification.dataset.dismissTimeout = timeout
  }


  close(event) {
    const notification = event.currentTarget.closest('[data-toast-target="notification"]')
    this.dismiss(notification)
  }

  dismiss(notification) {
    // Clear the auto-dismiss timeout if it exists
    if (notification.dataset.dismissTimeout) {
      clearTimeout(parseInt(notification.dataset.dismissTimeout))
      delete notification.dataset.dismissTimeout
    }
    
    this.addLeaveAnimation(notification)
    setTimeout(() => {
      notification.remove()
      // Don't remove the container - keep it so new toasts can be added
    }, 200)
  }

  dismissAll() {
    this.notificationTargets.forEach(notification => {
      this.dismiss(notification)
    })
  }

  addEnterAnimation(element) {
    element.classList.add('opacity-0', 'translate-x-full')
    requestAnimationFrame(() => {
      element.classList.remove('opacity-0', 'translate-x-full')
      element.classList.add('opacity-100', 'translate-x-0')
    })
  }

  addLeaveAnimation(element) {
    element.classList.remove('opacity-100', 'translate-x-0')
    element.classList.add('opacity-0', 'translate-x-full')
  }
}