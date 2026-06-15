import { Controller } from "@hotwired/stimulus"

// A lightweight controller that only handles showing and hiding dialogs.
// Usage:
//   <button data-controller="basic-modal"
//           data-basic-modal-dialog-value="my_dialog"
//           data-action="click->basic-modal#open">Open</button>
//
//   <dialog id="my_dialog" data-controller="basic-modal">
//     <button data-action="click->basic-modal#close">Close</button>
//   </dialog>
export default class extends Controller {
  static values = {
    dialog: String,
  }

  open(event) {
    event?.preventDefault?.()
    const dialog = this.#findDialog(event)
    if (!dialog) {
      console.warn("BasicModalController: Could not find dialog to open")
      return
    }

    // Remove display:none if present
    if (dialog.style.display === "none") {
      dialog.style.display = ""
    }
    
    // Use showModal() for native dialog elements
    if (typeof dialog.showModal === "function") {
      dialog.showModal()
    } else {
      // Fallback for non-dialog elements
      dialog.style.display = "block"
    }
  }

  close(event) {
    event?.preventDefault?.()
    
    let dialog = null
    
    // If the controller is attached to the dialog itself, use this.element
    if (this.element.tagName === "DIALOG") {
      dialog = this.element
    }
    // If the event target is inside a dialog, find it by traversing up
    else if (event?.currentTarget) {
      dialog = event.currentTarget.closest("dialog")
    }
    
    // If still not found, try to find by ID from the data attribute
    if (!dialog) {
      dialog = this.#findDialog(event)
    }

    if (!dialog) {
      console.warn("BasicModalController: Could not find dialog to close")
      return
    }

    // Close the dialog
    if (typeof dialog.close === "function") {
      dialog.close()
    }
    // Fallback: hide it manually if close() doesn't work
    dialog.style.display = "none"
  }

  #findDialog(event) {
    const dialogId = this.#dialogIdFromContext()
    if (!dialogId) return null
    return document.getElementById(dialogId)
  }

  #dialogIdFromContext() {
    // First check if we have a dialog value (from data-basic-modal-dialog-value)
    if (this.hasDialogValue) return this.dialogValue
    
    // Then check dataset attribute
    if (this.element?.dataset?.basicModalDialog) {
      return this.element.dataset.basicModalDialog
    }
    
    return null
  }
}


