import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="file-visibility"
export default class extends Controller {
  static values = {
    fileId: String,
    folderId: String,
    visibility: String
  }

  connect() {
  }

  async changeVisibility(event) {
    event.preventDefault();
    event.stopPropagation();

    const button = event.currentTarget;
    const fileId = button.dataset.fileId;
    const folderId = button.dataset.folderId || 'all';
    const newVisibility = button.dataset.visibility;

    // Close dropdown first
    const dropdown = button.closest('[data-controller="dropdown"]');
    if (dropdown) {
      const menu = dropdown.querySelector('[data-dropdown-target="menu"]');
      if (menu) {
        menu.classList.add("hidden");
      }
    }

    try {
      // Show loading state
      const originalText = button.textContent;
      button.textContent = "Updating...";
      button.disabled = true;

      const url = `/library/folders/${folderId}/uploads/${fileId}/update_visibility`;

      const response = await fetch(url, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest",
        },
        body: JSON.stringify({ visibility: newVisibility })
      });

      const contentType = response.headers.get("content-type");
      if (response.ok) {
        let result;
        if (contentType && contentType.includes("application/json")) {
          result = await response.json();
        } else {
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

        // Refresh the folder content
        this.refreshFolderContent();
      } else {
        const error = await response.json();
        if (error.notification_html) {
          this.showError(null, error.type || "error", error.notification_html);
        } else {
          this.showError(error.message || "Failed to update visibility.");
        }
      }
    } catch (error) {
      console.error("Visibility update error:", error);
      this.showError("Network error. Please check your connection.");
    } finally {
      // Reset button state
      button.disabled = false;
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

