import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="upload-dialog"
export default class extends Controller {
  static targets = ["folderSelection", "folderSelect"];

  connect() {
    // Reset folder selection visibility when dialog opens
    if (this.hasFolderSelectionTarget) {
      this.folderSelectionTarget.style.display = 'block';
    }
  }
}

