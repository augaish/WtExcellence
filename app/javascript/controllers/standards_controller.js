import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async deleteStandard(event) {
    event.preventDefault()
    const button = event.currentTarget
    const standardId = button.dataset.standardId
    const standardName = button.dataset.standardName || "this standard"

    if (!standardId) {
      console.error("Standard ID not found")
      return
    }

    const url = `/standards/${standardId}`
    const csrfToken = document.querySelector('meta[name="csrf-token"]').content

    const doDelete = async () => {
      const response = await fetch(url, {
        method: "DELETE",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        }
      })
      const data = await response.json()
      if (data.success) {
        const card = document.querySelector(`[data-standard-id="${standardId}"]`)
        if (card) {
          card.style.transition = "opacity 0.3s ease-out"
          card.style.opacity = "0"
          setTimeout(() => {
            card.remove()
            const grid = document.querySelector('.grid.gap-6')
            if (grid && grid.children.length === 0) {
              const contentContainer = grid.parentElement
              if (contentContainer) {
                contentContainer.innerHTML = `
                  <div class="text-center py-12">
                    <p class="text-gray-500 text-lg">No standards found</p>
                  </div>
                `
              }
            }
          }, 300)
        }
        this.showNotification(data.message || "Standard deleted successfully", "success")
      } else {
        this.showNotification(data.error || "Failed to delete standard", "error")
        throw new Error(data.error || "Failed to delete standard")
      }
    }

    let confirmed = false
    try {
      if (typeof window.showConfirmationModal !== 'function') {
        const { showConfirmationModal } = await import("helpers/confirmation_modal")
        window.showConfirmationModal = showConfirmationModal
      }

      if (typeof window.showConfirmationModal === 'function') {
        confirmed = await window.showConfirmationModal(
          `Are you sure you want to delete "${standardName}"? This action cannot be undone and will delete all associated data including versions, clauses, and checkpoints.`,
          {
            title: "Delete Standard",
            confirmText: "Delete",
            buttonStyle: "danger",
            loadingText: "Deleting...",
            asyncConfirm: doDelete
          }
        )
      } else {
        confirmed = confirm(
          `Are you sure you want to delete "${standardName}"? This action cannot be undone and will delete all associated data including versions, clauses, and checkpoints.`
        )
        if (confirmed) {
          await doDelete()
        }
      }
    } catch (error) {
      console.error("Error loading confirmation modal or deleting standard:", error)
      if (!confirmed) {
        confirmed = confirm(
          `Are you sure you want to delete "${standardName}"? This action cannot be undone and will delete all associated data including versions, clauses, and checkpoints.`
        )
        if (confirmed) {
          await doDelete().catch((e) => {
            this.showNotification("An error occurred while deleting the standard", "error")
          })
        }
      } else {
        this.showNotification("An error occurred while deleting the standard", "error")
      }
    }
  }

  // Re-enqueue a failed standard import (PDF is still stored server-side),
  // then reload so the card flips to processing and live polling resumes.
  async retryIngestion(event) {
    const button = event.currentTarget
    const standardId = button.dataset.standardId
    if (!standardId) return

    button.disabled = true
    try {
      const response = await fetch(`/standards/${standardId}/retry_ingestion`, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Accept": "application/json"
        }
      })
      const data = await response.json()
      if (response.ok && data.success) {
        window.location.reload()
      } else {
        button.disabled = false
        this.showNotification(data.error || "Could not retry the import", "error")
      }
    } catch (e) {
      button.disabled = false
      this.showNotification("Could not retry the import", "error")
    }
  }

  showNotification(message, type = "success") {
    // Dispatch custom event for toast controller to handle
    const event = new CustomEvent("toast:show", {
      detail: { 
        notificationHtml: message,
        type: type
      },
      bubbles: true
    })
    document.dispatchEvent(event)
  }
}
