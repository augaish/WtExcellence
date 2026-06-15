import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="tools--select-all"
export default class extends Controller {
  static targets = ["master", "item"]
  static values = {
    confirmTitle: { type: String, default: "Delete Tools" },
    confirmMessage: { type: String, default: "Are you sure you want to delete %{n} tool(s)? This action cannot be undone." },
    confirmText: { type: String, default: "Delete" },
    noSelectionMessage: { type: String, default: "Please select at least one tool to delete." },
    bulkDeletePath: { type: String, default: "/tools/bulk_destroy" }
  }

  connect() {
    this.updateBulkActionsVisibility()
  }

  toggleAll() {
    const checked = this.hasMasterTarget ? this.masterTarget.checked : false
    this.itemTargets.forEach((checkbox) => {
      checkbox.checked = checked
    })
    if (this.hasMasterTarget) {
      this.masterTarget.indeterminate = false
    }
    this.updateBulkActionsVisibility()
  }

  syncMaster() {
    if (!this.hasMasterTarget) return
    const total = this.itemTargets.length
    const checkedCount = this.itemTargets.filter((c) => c.checked).length
    if (checkedCount === 0) {
      this.masterTarget.checked = false
      this.masterTarget.indeterminate = false
    } else if (checkedCount === total) {
      this.masterTarget.checked = true
      this.masterTarget.indeterminate = false
    } else {
      this.masterTarget.checked = false
      this.masterTarget.indeterminate = true
    }
    this.updateBulkActionsVisibility()
  }

  getSelectedToolIds() {
    return this.itemTargets
      .filter((checkbox) => checkbox.checked)
      .map((checkbox) => checkbox.dataset.toolId)
      .filter((id) => id !== undefined && id !== "")
  }

  updateBulkActionsVisibility() {
    const selectedCount = this.getSelectedToolIds().length
    const bulkActionsElement = document.querySelector('[data-tools--select-all-target="bulkActions"]')
    if (!bulkActionsElement) return

    if (selectedCount > 0) {
      bulkActionsElement.classList.remove("hidden")
      bulkActionsElement.classList.add("flex")
    } else {
      bulkActionsElement.classList.add("hidden")
      bulkActionsElement.classList.remove("flex")
    }

    const countElement = bulkActionsElement.querySelector('[data-tools--select-all-target="selectedCount"]')
    if (countElement) {
      countElement.textContent = selectedCount
    }
  }

  async bulkDelete(event) {
    event.preventDefault()

    const selectedIds = this.getSelectedToolIds()
    if (selectedIds.length === 0) {
      alert(this.noSelectionMessageValue)
      return
    }

    const modal = document.getElementById("generalConfirmationModal")
    if (!modal) {
      console.error("General confirmation modal not found")
      return
    }
    const modalController = this.application.getControllerForElementAndIdentifier(
      modal,
      "general-confirmation"
    )
    if (!modalController) {
      console.error("General confirmation controller not found")
      return
    }

    const message = this.confirmMessageValue.replace("%{n}", selectedIds.length)
    const confirmed = await modalController.confirm(message, {
      title: this.confirmTitleValue,
      confirmText: this.confirmTextValue,
      buttonStyle: "danger"
    })

    if (!confirmed) return

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      const response = await fetch(this.bulkDeletePathValue, {
        method: "DELETE",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken
        },
        credentials: "same-origin",
        body: JSON.stringify({ tool_ids: selectedIds })
      })

      const data = await response.json().catch(() => ({}))

      if (response.ok && data.success) {
        window.location.reload()
      } else {
        alert(data.error || "Failed to delete tools")
      }
    } catch (err) {
      console.error("Bulk delete failed:", err)
      alert("Failed to delete tools. Please try again.")
    }
  }
}
