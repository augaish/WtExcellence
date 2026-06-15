import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="folder-delete"
export default class extends Controller {

  connect() {
  }

  openDeleteDialog(event) {
    event.preventDefault();
    event.stopPropagation();

    const button = event.currentTarget;
    const folderId = button.dataset.folderId;
    const folderName = button.dataset.folderName;
    const filesCount = parseInt(button.dataset.folderFilesCount) || 0;

    // Close dropdown first
    const dropdown = button.closest('[data-controller="dropdown"]');
    if (dropdown) {
      const menu = dropdown.querySelector('[data-dropdown-target="menu"]');
      if (menu) {
        menu.classList.add("hidden");
      }
    }

    // Update dialog content
    const nameElement = document.getElementById("folder_delete_name");
    const warningElement = document.getElementById(
      "folder_delete_files_warning"
    );
    const confirmButton = document.getElementById("confirm_delete_folder_btn");

    if (nameElement) {
      nameElement.textContent = folderName;
    }

    if (warningElement) {
      if (filesCount > 0) {
        const filesText = filesCount === 1 ? "file" : "files";
        warningElement.textContent = `This folder contains ${filesCount} ${filesText}. All files will be permanently deleted.`;
      } else {
        warningElement.textContent = "This folder is empty.";
      }
    }

    // Store folder ID on confirm button
    if (confirmButton) {
      confirmButton.dataset.folderId = folderId;
      // Remove existing listeners
      const newConfirmButton = confirmButton.cloneNode(true);
      confirmButton.parentNode.replaceChild(newConfirmButton, confirmButton);
      newConfirmButton.addEventListener("click", () =>
        this.deleteFolder(folderId)
      );
    }

    // Open dialog
    const dialog = document.getElementById("delete_folder_dialog");
    if (dialog) {
      dialog.showModal();
    }
  }

  async deleteFolder(folderId) {
    const confirmButton = document.getElementById("confirm_delete_folder_btn");
    const originalText = confirmButton.textContent;

    try {
      // Show loading state
      confirmButton.textContent = "Deleting...";
      confirmButton.disabled = true;

      const response = await fetch(`/library/folders/${folderId}`, {
        method: "DELETE",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')
            .content,
          "Content-Type": "application/json",
        },
      });

      if (response.ok) {
        const result = await response.json();
        if (result.notification_html) {
          this.showSuccess(null, result.type || "success", result.notification_html);
        }

        // Close dialog
        const dialog = document.getElementById("delete_folder_dialog");
        if (dialog) {
          dialog.close();
        }

        // Refresh folders grid via Turbo Frame without full page reload
        this.refreshFoldersGrid();
      } else {
        const error = await response.json();
        if (error.notification_html) {
          this.showError(null, error.type || "error", error.notification_html);
        }
      }
    } catch (error) {
      console.error("Delete error:", error);
      this.showError("Network error. Please check your connection.");
    } finally {
      // Reset button state
      confirmButton.textContent = originalText;
      confirmButton.disabled = false;
    }
  }

  showSuccess(message, type = "success", notificationHtml = null) {
    this.dispatchToast(notificationHtml);
  }

  showError(message, type = "error", notificationHtml = null) {
    this.dispatchToast(notificationHtml);
  }

  dispatchToast(notificationHtml) {
    if (!notificationHtml) return;

    // Dispatch custom event for toast controller to handle
    const event = new CustomEvent('toast:show', {
      detail: { notificationHtml },
      bubbles: true
    });
    document.dispatchEvent(event);
  }

  refreshFoldersGrid() {
    // Refresh the folders grid Turbo Frame without full page reload
    const foldersGridFrame = document.querySelector('turbo-frame#folders_grid');
    if (foldersGridFrame) {
      // Get the current URL parameters to preserve search/sort
      const url = new URL(window.location);
      // Force reload by clearing src first, then setting it
      const currentSrc = foldersGridFrame.src;
      foldersGridFrame.src = '';
      // Use setTimeout to ensure the frame reloads
      setTimeout(() => {
        foldersGridFrame.src = url.pathname + url.search;
      }, 10);
      return;
    }

    // If not on index page, check if we're in a folder view
    const folderContentFrame = document.querySelector('turbo-frame#folder_content');
    if (folderContentFrame) {
      // Refresh the folder content frame
      const url = new URL(window.location);
      const currentSrc = folderContentFrame.src;
      folderContentFrame.src = '';
      setTimeout(() => {
        folderContentFrame.src = url.pathname + url.search;
      }, 10);
      return;
    }

    // Fallback: reload the entire page
    window.location.reload();
  }
}
