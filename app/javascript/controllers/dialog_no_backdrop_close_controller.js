import { Controller } from "@hotwired/stimulus"

/**
 * Prevents the dialog from closing when the user clicks outside (on the backdrop).
 * The dialog will only close when the user clicks an explicit close button or action.
 *
 * Add to any <dialog> element: data-controller="dialog-no-backdrop-close"
 */
export default class extends Controller {
  connect() {
    this.boundPreventClose = this.#preventClose.bind(this)
    this.element.addEventListener("cancel", this.boundPreventClose)
  }

  disconnect() {
    this.element.removeEventListener("cancel", this.boundPreventClose)
  }

  #preventClose(event) {
    event.preventDefault()
  }
}
