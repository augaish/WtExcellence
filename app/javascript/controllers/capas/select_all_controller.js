import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="capas--select-all"
export default class extends Controller {
  static targets = ["master", "item"]

  connect() {
    this.updateBulkActionsVisibility()
  }

  toggleAll() {
    const checked = this.masterTarget.checked
    this.itemTargets.forEach((checkbox) => {
      checkbox.checked = checked
    })
    this.updateIndeterminate()
    this.updateBulkActionsVisibility()
  }

  syncMaster() {
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

  updateIndeterminate() {
    // After toggling all, master should not be indeterminate
    this.masterTarget.indeterminate = false
  }

  getSelectedCapaIds() {
    return this.itemTargets
      .filter((checkbox) => checkbox.checked)
      .map((checkbox) => checkbox.dataset.capaId)
      .filter((id) => id !== undefined)
  }

  updateBulkActionsVisibility() {
    const selectedCount = this.getSelectedCapaIds().length
    // Find bulkActions element using querySelector since it's outside the controller's scope
    const bulkActionsElement = document.querySelector('[data-capas--select-all-target="bulkActions"]')
    if (bulkActionsElement) {
      if (selectedCount > 0) {
        bulkActionsElement.classList.remove("hidden")
        bulkActionsElement.style.display = "flex"
      } else {
        bulkActionsElement.classList.add("hidden")
        bulkActionsElement.style.display = "none"
      }
    } else {
      console.warn("bulkActions element not found")
    }
  }
}


