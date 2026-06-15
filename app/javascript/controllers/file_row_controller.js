import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="file-row"
export default class extends Controller {
  static values = {
    folderId: String,
    fileId: String
  }

  openFile(event) {
    // Don't open file if clicking on interactive elements
    const target = event.target;
    const isInteractive = target.closest('button, a, input[type="checkbox"], input[type="radio"], [data-controller="dropdown"], [data-dropdown-target="menu"], [data-dropdown-target="menu"] *');
    
    if (isInteractive) {
      return; // Let the button/link/checkbox handle the click
    }

    // Navigate to file view page using Turbo
    const url = `/library/folders/${this.folderIdValue}/uploads/${this.fileIdValue}`;
    Turbo.visit(url);
  }
}

