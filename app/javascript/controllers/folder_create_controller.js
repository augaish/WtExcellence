import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["parentId", "parentInfo", "parentName"];

  connect() {
    // Listen for modal open events to set parent folder
    document.addEventListener("click", this.handleCreateSubfolderClick.bind(this));
    
    // Also listen for when modal is closed
    const dialog = this.element.closest('dialog');
    if (dialog) {
      dialog.addEventListener('close', this.reset.bind(this));
    }
  }

  disconnect() {
    document.removeEventListener("click", this.handleCreateSubfolderClick.bind(this));
  }

  handleCreateSubfolderClick(event) {
    const button = event.target.closest('[data-folder-parent-id]');
    if (!button) return;

    // Wait a bit for the modal to open
    setTimeout(() => {
      const parentId = button.dataset.folderParentId;
      const parentName = button.dataset.folderParentName;

      if (parentId && parentName && this.hasParentIdTarget && this.hasParentInfoTarget && this.hasParentNameTarget) {
        // Set parent ID
        this.parentIdTarget.value = parentId;
        
        // Show parent folder info
        this.parentInfoTarget.classList.remove("hidden");
        this.parentNameTarget.textContent = parentName;
      }
    }, 100);
  }

  // Reset when modal is closed
  reset() {
    this.parentIdTarget.value = "";
    this.parentInfoTarget.classList.add("hidden");
    this.parentNameTarget.textContent = "";
  }
}

