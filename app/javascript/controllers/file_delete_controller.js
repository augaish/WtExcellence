import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="file-delete"
export default class extends Controller {

  connect() {
  }

  openDeleteDialog(event) {
    event.preventDefault();
    event.stopPropagation();

    const button = event.currentTarget;
    const fileId = button.dataset.fileId;
    const fileName = button.dataset.fileName;
    const folderId = button.dataset.folderId || 'all';

    // Close dropdown first
    const dropdown = button.closest('[data-controller="dropdown"]');
    if (dropdown) {
      const menu = dropdown.querySelector('[data-dropdown-target="menu"]');
      if (menu) {
        menu.classList.add("hidden");
      }
    }

    // Update dialog content
    const nameElement = document.getElementById("file_delete_name");
    const confirmButton = document.getElementById("confirm_delete_file_btn");

    if (nameElement) {
      nameElement.textContent = fileName;
    }

    // Store file ID and folder ID on confirm button
    if (confirmButton) {
      confirmButton.dataset.fileId = fileId;
      confirmButton.dataset.folderId = folderId;
      // Remove existing listeners
      const newConfirmButton = confirmButton.cloneNode(true);
      confirmButton.parentNode.replaceChild(newConfirmButton, confirmButton);
      newConfirmButton.addEventListener("click", () =>
        this.deleteFile(fileId, folderId)
      );
    }

    // Open dialog
    const dialog = document.getElementById("delete_file_dialog");
    if (dialog) {
      dialog.showModal();
    }
  }

  async deleteFile(fileId, folderId) {
    const confirmButton = document.getElementById("confirm_delete_file_btn");
    const originalText = confirmButton.textContent;

    try {
      // Show loading state
      confirmButton.textContent = "Deleting...";
      confirmButton.disabled = true;

      // Construct URL based on folder_id
      // If folder_id is 'all' or not provided, we need to handle it differently
      // The route requires a folder_id, so we'll use 'all' as the folder_id
      const url = `/library/folders/${folderId || 'all'}/uploads/${fileId}`;

      const response = await fetch(url, {
        method: "DELETE",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')
            .content,
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest",
        },
      });

      // Check if response is actually JSON
      const contentType = response.headers.get("content-type");
      if (response.ok) {
        let result;
        if (contentType && contentType.includes("application/json")) {
          result = await response.json();
        } else {
          console.error("Expected JSON response but got:", contentType);
          // Try to parse as JSON anyway
          try {
            result = await response.json();
          } catch (e) {
            console.error("Failed to parse response as JSON:", e);
            this.showError("Unexpected response format. Please refresh the page.");
            return;
          }
        }
        if (result.notification_html) {
          this.showSuccess(null, result.type || "success", result.notification_html);
        }

        // Close dialog
        const dialog = document.getElementById("delete_file_dialog");
        if (dialog) {
          dialog.close();
        }

        // Refresh the folder content Turbo Frame
        this.refreshFolderContent();
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

  refreshFolderContent() {
    // Refresh the folder content Turbo Frame without full page reload
    const folderContentFrame = document.querySelector('turbo-frame#folder_content');
    if (folderContentFrame) {
      // Get the current URL parameters to preserve search/sort/filters
      const url = new URL(window.location);
      // Use Turbo to visit the frame's source
      folderContentFrame.src = url.pathname + url.search;
    } else {
      // If not in a folder view, reload the page
      window.location.reload();
    }
  }
}

