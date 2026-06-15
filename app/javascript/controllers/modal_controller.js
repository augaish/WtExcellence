import { Controller } from "@hotwired/stimulus";

// Global polling registry to prevent duplicate polling across all controller instances
// This ensures only one polling interval per standard ID, even if multiple controllers exist
const globalPollingRegistry = new Map(); // Map of standard_id -> { intervalId, controller }

// Connects to data-controller="modal"
export default class extends Controller {
  static values = {
    pollingInterval: { type: Number, default: 3000 } // Poll every 3 seconds
  }

  connect() {
    this.pollingIntervals = new Map(); // Map of standard_id -> intervalId (local tracking)
    this.isStartingPolling = false; // Flag to prevent concurrent polling starts
    this.pollingDebounceTimer = null; // Debounce timer for polling starts

    // Listen for turbo frame loads to restart polling after navigation/filtering
    // This handles both initial page load and subsequent navigations
    this.boundHandleTurboFrameLoad = this.handleTurboFrameLoad.bind(this);
    this.boundStartPolling = this.debouncedStartPolling.bind(this);

    document.addEventListener('turbo:frame-load', this.boundHandleTurboFrameLoad);
    document.addEventListener('turbo:load', this.boundStartPolling);

    // Also check immediately in case DOM is already ready (for non-Turbo navigations)
    // But use a delay to ensure cards are rendered
    this.debouncedStartPolling();
  }

  debouncedStartPolling() {
    // Clear any existing debounce timer
    if (this.pollingDebounceTimer) {
      clearTimeout(this.pollingDebounceTimer);
    }

    // Debounce polling start to prevent multiple rapid calls
    this.pollingDebounceTimer = setTimeout(() => {
      this.startPollingForProcessingCards();
      this.pollingDebounceTimer = null;
    }, 500); // Wait 500ms after last event before starting polling
  }

  disconnect() {
    // Clear debounce timer
    if (this.pollingDebounceTimer) {
      clearTimeout(this.pollingDebounceTimer);
      this.pollingDebounceTimer = null;
    }

    // Remove event listeners
    if (this.boundHandleTurboFrameLoad) {
      document.removeEventListener('turbo:frame-load', this.boundHandleTurboFrameLoad);
    }
    if (this.boundStartPolling) {
      document.removeEventListener('turbo:load', this.boundStartPolling);
    }

    // Clean up all polling intervals when controller disconnects
    // Only stop intervals that belong to this controller instance
    this.pollingIntervals.forEach((intervalId, standardId) => {
      const globalEntry = globalPollingRegistry.get(standardId);
      if (globalEntry && globalEntry.controller === this && globalEntry.intervalId === intervalId) {
        clearInterval(intervalId);
        globalPollingRegistry.delete(standardId);
      }
    });
    this.pollingIntervals.clear();
    this.isStartingPolling = false;
  }

  handleTurboFrameLoad(event) {
    // Check if the loaded frame is the standards_content frame
    const frame = event.target;
    if (frame.id === 'standards_content') {
      // Use debounced polling start to prevent multiple rapid calls
      this.debouncedStartPolling();
    }
  }


  show(event) {
    const dialogId = event.params.dialog;
    const dialog = document.getElementById(dialogId);
    if (dialog) {
      dialog.showModal();
    }
  }

  open(event) {
    const dialogId = event.params.dialog;
    const dialog = document.getElementById(dialogId);
    if (dialog) {
      // Remove display: none if present (for dialogs that need to stay hidden initially)
      if (dialog.style.display === 'none') {
        dialog.style.display = '';
      }

      // Handle assign standard dialog - trigger version loading
      if (dialogId.startsWith("assignStandardDialog")) {
        const assignController = this.application.getControllerForElementAndIdentifier(dialog, 'assign-standard');
        if (assignController) {
          // Call open() BEFORE showModal() so standard ID is always set before the dialog is visible
          assignController.open({
            target: event.target,
            currentTarget: event.currentTarget || event.target
          });
        }
      }

      // Handle move file dialog - populate form fields
      if (dialogId === "move_file_dialog") {
        const uploadId = event.target.getAttribute("data-move-file-id");
        const fileName = event.target.getAttribute("data-move-file-name");
        const currentFolderId = event.target.getAttribute("data-move-file-current-folder");

        const fileIdInput = dialog.querySelector("#move_file_upload_id");
        const fileNameInput = dialog.querySelector("#move_file_name");
        const folderSelect = dialog.querySelector("#move_file_folder_id");

        if (fileIdInput) fileIdInput.value = uploadId || "";
        if (fileNameInput) fileNameInput.value = fileName || "";
        if (folderSelect) folderSelect.value = currentFolderId || "";
      }

      // Handle upload document dialog - set visibility to private if uploading from Legal Documents
      if (dialogId === "upload_document_dialog") {
        const button = event.currentTarget;
        const isLegalDocuments = button.dataset.legalDocuments === "true";
        const folderId = button.dataset.folderId;

        if (isLegalDocuments) {
          // Auto-set visibility to private when uploading from Legal Documents
          const visibilitySelect = dialog.querySelector('select[name="upload[visibility]"]');
          if (visibilitySelect) {
            visibilitySelect.value = "private";
          }
        }

        // Set folder_id if provided
        if (folderId) {
          const folderSelect = dialog.querySelector('select[name="upload[folder_id]"]');
          if (folderSelect) {
            folderSelect.value = folderId;
          }
        }
      }

      // Handle create folder dialog - set parent folder if creating subfolder
      if (dialogId === "create_folder_dialog") {
        const button = event.currentTarget;
        const parentId = button.dataset.folderParentId;
        const parentName = button.dataset.folderParentName;

        if (parentId && parentName) {
          // Get the folder-create controller
          const form = dialog.querySelector('[data-controller*="folder-create"]');
          if (form) {
            const folderCreateController = this.application.getControllerForElementAndIdentifier(form, 'folder-create');
            if (folderCreateController) {
              // Set parent folder info after dialog opens
              setTimeout(() => {
                if (folderCreateController.hasParentIdTarget) {
                  folderCreateController.parentIdTarget.value = parentId;
                }
                if (folderCreateController.hasParentInfoTarget) {
                  folderCreateController.parentInfoTarget.classList.remove("hidden");
                }
                if (folderCreateController.hasParentNameTarget) {
                  folderCreateController.parentNameTarget.textContent = parentName;
                }
              }, 50);
            }
          }
        }
      }

      // Handle upload document dialog - set folder ID if uploading from within a folder
      if (dialogId === "upload_document_dialog") {
        const button = event.currentTarget;
        const folderId = button.dataset.folderId;

        if (folderId) {
          // Get the upload-dialog controller
          const uploadDialogController = this.application.getControllerForElementAndIdentifier(dialog, 'upload-dialog');
          if (uploadDialogController) {
            // Set folder ID and hide selection after dialog opens
            setTimeout(() => {
              if (uploadDialogController.hasFolderSelectTarget) {
                uploadDialogController.folderSelectTarget.value = folderId;
              }
              if (uploadDialogController.hasFolderSelectionTarget) {
                uploadDialogController.folderSelectionTarget.style.display = 'none';
              }
            }, 50);
          }
        } else {
          // Show folder selection if no folder ID
          const uploadDialogController = this.application.getControllerForElementAndIdentifier(dialog, 'upload-dialog');
          if (uploadDialogController && uploadDialogController.hasFolderSelectionTarget) {
            uploadDialogController.folderSelectionTarget.style.display = 'block';
          }
        }
      }

      dialog.showModal();

      // Store capa_id, optional capa_action_id, and optional assignment_id from the button that opened the modal if present
      const button = event.currentTarget;
      const capaId = button.dataset.capaId;
      const capaActionId = button.dataset.capaActionId;
      if (dialog.id === 'upload_document_dialog') {
        if (capaId) dialog.dataset.capaId = capaId; else delete dialog.dataset.capaId;
        if (capaActionId) dialog.dataset.capaActionId = capaActionId; else delete dialog.dataset.capaActionId;
        const assignmentId = button.dataset.assignmentId;
        if (assignmentId) dialog.dataset.assignmentId = assignmentId; else delete dialog.dataset.assignmentId;
        const checklistItemId = button.dataset.checklistItemId;
        if (checklistItemId) dialog.dataset.checklistItemId = checklistItemId; else delete dialog.dataset.checklistItemId;
      }
    }
  }

  close(event) {
    const dialog = event.target.closest("dialog");
    if (dialog) {
      dialog.close();
      // Reset folder-create controller if present
      const folderCreateController = this.application.getControllerForElementAndIdentifier(
        dialog.querySelector('[data-controller*="folder-create"]'),
        'folder-create'
      );
      if (folderCreateController && folderCreateController.reset) {
        folderCreateController.reset();
      }
    }
  }

  closeById(event) {
    const dialogId = event.params.dialog;
    const dialog = document.getElementById(dialogId);
    if (dialog) {
      dialog.close();
      // Reset folder-create controller if present
      const folderCreateController = this.application.getControllerForElementAndIdentifier(
        dialog.querySelector('[data-controller*="folder-create"]'),
        'folder-create'
      );
      if (folderCreateController && folderCreateController.reset) {
        folderCreateController.reset();
      }
    }
  }

  handleExport(event) {
    event.preventDefault();

    const form = event.target;
    const formData = new FormData(form);
    const action = form.getAttribute('action');

    // Build query string from form data
    const params = new URLSearchParams();
    formData.forEach((value, key) => {
      params.append(key, value);
    });

    // Create export URL with query parameters
    const exportUrl = `${action}?${params.toString()}`;

    // Trigger download using a hidden iframe (simpler and cleaner)
    const iframe = document.createElement('iframe');
    iframe.style.display = 'none';
    iframe.src = exportUrl;
    document.body.appendChild(iframe);

    // Remove iframe after download starts
    setTimeout(() => {
      document.body.removeChild(iframe);
    }, 1000);

    // Close the modal
    const dialog = form.closest('dialog');
    if (dialog) {
      dialog.close();
    }
  }

  async submitUploadForm(event) {
    await this.submitForm(event);
  }

  async submitForm(event) {
    event.preventDefault();

    const form = event.target;
    const formData = new FormData(form);

    // Try multiple selectors to find submit button
    const submitButton =
      form.querySelector("#upload_submit_btn") ||
      form.querySelector('button[type="submit"]') ||
      form.querySelector('input[type="submit"]');

    // Handle case where submit button might not exist
    let originalText = "";
    const textSpan = submitButton?.querySelector("[data-submit-button-text]");
    const spinner = submitButton?.querySelector("[data-submit-spinner]");
    if (submitButton) {
      originalText = textSpan ? textSpan.textContent : (submitButton.textContent || submitButton.value || "Submit");
    } else {
      console.warn("Submit button not found in form");
    }

    // Determine which form is being submitted
    // Order matters: check most specific forms first
    const isFolderForm =
      form.id === "create_folder_form" || form.querySelector("#folder_name");
    const isMoveFileForm =
      form.id === "move_file_form" || form.querySelector("#move_file_upload_id");
    const isStandardForm =
      form.querySelector("#standard_name") && form.querySelector("#pdf_upload");
    const isUploadForm =
      form.id === "upload_document_form" ||
      (form.querySelector('input[type="file"]') && !isStandardForm);

    let url, loadingText, body;
    if (isFolderForm) {
      url = "/library/folders";
      loadingText = "Creating...";
      // Convert FormData to JSON for folder creation
      const data = {};
      formData.forEach((value, key) => {
        // Handle nested keys like "folder[folder_name]" -> extract "folder_name"
        if (key.startsWith('folder[') && key.endsWith(']')) {
          const nestedKey = key.slice(7, -1); // Remove "folder[" and "]"
          data[nestedKey] = value;
        } else {
          data[key] = value;
        }
      });
      body = JSON.stringify({ folder: data });
    } else if (isMoveFileForm) {
      url = "/library/files/move";
      loadingText = "Moving...";
      // Convert FormData to JSON for move file
      const data = {};
      formData.forEach((value, key) => {
        data[key] = value;
      });
      body = JSON.stringify(data);
    } else if (isStandardForm) {
      // Check standard form BEFORE upload form since standard forms also have file inputs
      loadingText = "Uploading...";
      // Send locale in URL and body so backend returns translated errors (e.g. Arabic)
      const pageLocale =
        document.querySelector('meta[name="locale"]')?.getAttribute("content") ||
        document.documentElement.getAttribute("lang") ||
        (document.documentElement.lang || "en");
      formData.append("locale", pageLocale);
      url = `/standards/upload_standard?locale=${encodeURIComponent(pageLocale)}`;
      body = formData;
    } else if (isUploadForm) {
      url = "/uploads";
      loadingText = "Uploading...";

      // Check if this is a CAPA or CAPA action upload (check dialog for capa_id / capa_action_id)
      const dialog = form.closest('dialog');
      const capaId = dialog?.dataset?.capaId;
      const capaActionId = dialog?.dataset?.capaActionId;
      const assignmentId = dialog?.dataset?.assignmentId;
      if (capaId) formData.append('capa_id', capaId);
      if (capaActionId) formData.append('capa_action_id', capaActionId);

      body = formData; // Keep as FormData for file upload
    } else {
      this.showError("Unknown form type");
      return;
    }

    try {
      // Show loading state
      if (submitButton) {
        if (spinner) spinner.classList.remove("hidden");
        if (textSpan) {
          textSpan.textContent = loadingText;
        } else if (submitButton.tagName === "BUTTON") {
          submitButton.textContent = loadingText;
        } else {
          submitButton.value = loadingText;
        }
        submitButton.disabled = true;
      }

      const headers = {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')
          .content,
      };

      if (isFolderForm || isMoveFileForm) {
        headers["Content-Type"] = "application/json";
      }
      // Don't set Content-Type for FormData - browser will set it with boundary

      const response = await fetch(url, {
        method: "POST",
        body: body,
        headers: headers,
      });

      if (response.ok) {
        const result = await response.json();
        // For folder creation: show success message and update folders grid
        if (isFolderForm) {
          if (result.notification_html) {
            this.showSuccess(null, result.type || "success", result.notification_html);
          }
          form.reset();
          this.close(event);

          // If creating a subfolder (has parent_id), reload the page to show it
          // Otherwise, just refresh the folders grid
          if (result.folder && result.folder.parent_id) {
            // It's a subfolder - reload the page
            window.location.reload();
          } else {
            // Root folder - update the folders grid via Turbo Frame without full page reload
            this.refreshFoldersGrid();
          }
          return;
        }
        // For move file: show success message and update DOM directly
        if (isMoveFileForm) {
          if (result.notification_html) {
            this.showSuccess(null, result.type || "success", result.notification_html);
          }
          form.reset();
          this.close(event);

          // Update DOM to reflect the file move
          this.updateFileMove(result.upload);
          return;
        }
        // For standard upload: show success and reload page to display standards
        if (isStandardForm) {
          if (result.notification_html) {
            this.showSuccess(null, result.type || "success", result.notification_html);
          }
          form.reset();
          this.close(event);
          window.location.reload();
          return;
        }
        // For upload form: show success and reload or update table
        if (isUploadForm) {
          const dialog = form.closest('dialog');
          const capaId = dialog?.dataset?.capaId;
          const capaActionId = dialog?.dataset?.capaActionId;
          const assignmentId = dialog?.dataset?.assignmentId;

          if (capaActionId && result.upload) {
            if (result.notification_html) {
              this.showSuccess(null, result.type || "success", result.notification_html);
            }
            form.reset();
            this.close(event);
            window.location.reload();
            return;
          }
          if (capaId && result.upload) {
            this.updateCapaDocumentsTable(result.upload, capaId);
            if (result.notification_html) {
              this.showSuccess(null, result.type || "success", result.notification_html);
            }
            form.reset();
            this.close(event);
            return;
          }
          if (assignmentId && result.upload) {
            try {
              const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
              if (csrfToken) {
                const checklistItemId = dialog?.dataset?.checklistItemId;
                const body = { upload_ids: [result.upload.id] };
                if (checklistItemId) body.checklist_item_id = checklistItemId;
                await fetch(`/assignments/${assignmentId}/link_documents`, {
                  method: "POST",
                  headers: {
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                    "X-CSRF-Token": csrfToken
                  },
                  body: JSON.stringify(body)
                });
              }
            } catch (e) {
              console.error("Failed to link upload to assignment:", e);
            }

            if (result.notification_html) {
              this.showSuccess(null, result.type || "success", result.notification_html);
            }
            form.reset();
            this.close(event);
            window.location.reload();
            return;
          }

          // Regular library upload - reload page
          if (result.notification_html) {
            this.showSuccess(null, result.type || "success", result.notification_html);
          }
          form.reset();
          this.close(event);
          window.location.reload();
          return;
        }
      } else {
        // Non-OK response: try to parse error body and always show something to the user
        let errorMessage = "Upload failed. Please try again.";
        try {
          const error = await response.json();
          if (error.notification_html) {
            this.showError(null, error.type || "error", error.notification_html);
            form.reset();
            this.close(event);
            return;
          }
          errorMessage = error.message || error.error || errorMessage;
          // Use Arabic message when backend sends both and page locale is Arabic
          const pageLang = (document.querySelector('meta[name="locale"]')?.getAttribute("content") || document.documentElement.getAttribute("lang") || "").toLowerCase();
          if (error.message_ar && (pageLang === "ar" || pageLang.startsWith("ar-"))) {
            errorMessage = error.message_ar;
          }
        } catch (parseError) {
          console.error("Error response is not JSON:", parseError);
          if (response.status >= 500) {
            errorMessage = "Server error. Please try again later.";
          } else if (response.status === 422) {
            errorMessage = "Invalid request. Please check your input and try again.";
          }
        }
        // Strip "Validation failed: " prefix so we only show the actual error (e.g. "Code has already been taken")
        const displayMessage =
          typeof errorMessage === "string"
            ? (errorMessage.replace(/^Validation failed:\s*/i, "").trim() || errorMessage)
            : errorMessage;
        this.showError(displayMessage);
        form.reset();
        this.close(event);
      }
    } catch (error) {
      console.error("Form submission error:", error);
      this.showError("Network error. Please check your connection.");
      this.close(event);
    } finally {
      // Reset button state
      if (submitButton) {
        if (spinner) spinner.classList.add("hidden");
        if (textSpan) {
          textSpan.textContent = originalText;
        } else if (submitButton.tagName === "BUTTON") {
          submitButton.textContent = originalText;
        } else {
          submitButton.value = originalText;
        }
        submitButton.disabled = false;
      }
    }
  }

  insertStandardCard(html, standardId) {
    // Find the standards content container (inside turbo_frame)
    const standardsContent = document.querySelector('#standards_content');
    if (!standardsContent) return null;

    // Find the p-6 container that holds either grid or empty state
    const contentContainer = standardsContent.querySelector('.p-6');
    if (!contentContainer) return null;

    // Check if grid exists - use a more flexible selector
    let grid = contentContainer.querySelector('.grid.gap-6');

    // Check if we're in empty state
    const emptyState = contentContainer.querySelector('.text-center.py-12');

    if (!grid && emptyState) {
      // We're in empty state - create grid and replace empty state
      grid = document.createElement('div');
      grid.className = 'grid grid-cols-1 lg:grid-cols-2 gap-6';
      contentContainer.innerHTML = '';
      contentContainer.appendChild(grid);
    } else if (!grid) {
      // No grid and no empty state - create grid
      grid = document.createElement('div');
      grid.className = 'grid grid-cols-1 lg:grid-cols-2 gap-6';
      contentContainer.appendChild(grid);
    }

    // Create a temporary container to parse the HTML
    const temp = document.createElement('div');
    temp.innerHTML = html.trim();
    const cardElement = temp.firstElementChild;

    if (cardElement) {
      // Add data attribute to identify the card by standard_id
      if (standardId) {
        cardElement.setAttribute('data-standard-id', standardId);
      }

      // Insert at the beginning of the grid
      grid.insertBefore(cardElement, grid.firstChild);

      return cardElement;
    }

    return null;
  }

  startPollingForProcessingCards() {
    // Prevent concurrent calls from creating duplicate polling
    if (this.isStartingPolling) {
      return;
    }

    this.isStartingPolling = true;

    try {
      // Find all cards that are currently processing
      const processingCards = document.querySelectorAll('[data-standard-id][data-processing="true"]');

      processingCards.forEach((card) => {
        const standardId = card.getAttribute('data-standard-id');
        if (standardId) {
          // Check global registry to see if already polling
          const globalEntry = globalPollingRegistry.get(standardId);
          if (!globalEntry || !globalEntry.intervalId) {
            // Only start polling if not already polling for this standard
            this.startPolling(standardId);
          } else {
            // Already polling globally, just track it locally
            this.pollingIntervals.set(standardId, globalEntry.intervalId);
          }
        }
      });
    } finally {
      // Use setTimeout to allow the intervals to be set before allowing next call
      setTimeout(() => {
        this.isStartingPolling = false;
      }, 200);
    }
  }

  startPolling(standardId) {
    // CRITICAL: Check global registry first to prevent duplicate polling
    // This ensures only one polling interval per standard ID across ALL controller instances
    const globalEntry = globalPollingRegistry.get(standardId);
    if (globalEntry && globalEntry.intervalId) {
      // Already polling globally, just track it locally
      this.pollingIntervals.set(standardId, globalEntry.intervalId);
      return;
    }

    // Stop any existing polling for this standard (safety check)
    this.stopPolling(standardId);

    let isPolling = true;
    const pollInterval = setInterval(async () => {
      // Double-check we should still be polling (in case it was stopped)
      const currentGlobalEntry = globalPollingRegistry.get(standardId);
      if (!isPolling || !currentGlobalEntry || currentGlobalEntry.intervalId !== pollInterval) {
        clearInterval(pollInterval);
        return;
      }

      try {
        const response = await fetch(`/standards/${standardId}/job_status`, {
          method: 'GET',
          headers: {
            'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
            'Accept': 'application/json'
          }
        });

        if (response.ok) {
          const result = await response.json();

          if (result.completed || result.failed) {
            // Job finished, stop polling
            isPolling = false;
            this.stopPolling(standardId);

            // Find the card element by standard_id
            const cardElement = document.querySelector(`[data-standard-id="${standardId}"]`);

            // Replace the card with updated HTML
            if (result.html && cardElement) {
              this.replaceStandardCard(cardElement, result.html);
            }

            // Card updates silently without alert notification
            return; // Exit early since we're done
          }
          // If not completed, continue polling
        } else {
          console.error('Failed to poll job status:', response.status);
          // Stop polling on error
          isPolling = false;
          this.stopPolling(standardId);
        }
      } catch (error) {
        console.error('Polling error:', error);
        // Stop polling on error
        isPolling = false;
        this.stopPolling(standardId);
      }
    }, this.pollingIntervalValue || 3000);

    // Store in global registry to prevent duplicates across all instances
    globalPollingRegistry.set(standardId, {
      intervalId: pollInterval,
      controller: this
    });

    // Also store locally for this controller instance
    this.pollingIntervals.set(standardId, pollInterval);
  }

  stopPolling(standardId) {
    // Check global registry first
    const globalEntry = globalPollingRegistry.get(standardId);
    if (globalEntry && globalEntry.intervalId) {
      clearInterval(globalEntry.intervalId);
      globalPollingRegistry.delete(standardId);
    }

    // Also clean up local tracking
    const localIntervalId = this.pollingIntervals.get(standardId);
    if (localIntervalId) {
      clearInterval(localIntervalId);
    }
    this.pollingIntervals.delete(standardId);
  }

  replaceStandardCard(oldCardElement, newHtml) {
    if (!oldCardElement || !newHtml) return;

    // Get the standard_id from the old card
    const standardId = oldCardElement.getAttribute('data-standard-id');

    // Create a temporary container to parse the new HTML
    const temp = document.createElement('div');
    temp.innerHTML = newHtml.trim();
    const newCardElement = temp.firstElementChild;

    if (newCardElement && oldCardElement.parentNode) {
      // Preserve the data-standard-id attribute if it exists
      if (standardId) {
        newCardElement.setAttribute('data-standard-id', standardId);
      }

      // Replace the old card with the new one
      oldCardElement.parentNode.replaceChild(newCardElement, oldCardElement);
    }
  }

  showSuccess(message, type = "success", notificationHtml = null) {
    this.dispatchToast(notificationHtml || message, "success");
  }

  showError(message, type = "error", notificationHtml = null) {
    this.dispatchToast(notificationHtml || message, "error");
  }

  dispatchToast(notificationHtmlOrMessage, type = "success") {
    let notificationHtml = notificationHtmlOrMessage;

    // If it's a plain message string, build notification HTML so errors are always shown
    if (!notificationHtmlOrMessage || (typeof notificationHtmlOrMessage === "string" && !notificationHtmlOrMessage.includes("data-toast-target"))) {
      const bgColor = type === "success"
        ? "bg-[#FFFFFF] border-[#E3E3E3] border-l-4 border-l-[#5C3984]"
        : "bg-[#FFFFFF] border-[#E3E3E3] border-l-4 border-l-red-500";
      const icon = type === "success"
        ? '<svg class="w-5 h-5 text-[#5C3984]" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/></svg>'
        : '<svg class="w-5 h-5 text-red-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/></svg>';
      notificationHtml = `
        <div data-toast-target="notification" class="${bgColor} rounded-lg shadow-lg p-4 flex items-start gap-3 transform opacity-0 translate-x-full transition ease-out duration-300">
          ${icon}
          <div class="flex-1 text-sm text-[#0D1120] font-medium">${notificationHtmlOrMessage || (type === "error" ? "Something went wrong." : "Operation completed")}</div>
          <button data-action="click->toast#close" class="text-gray-400 hover:text-gray-600 transition-colors">
            <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"/></svg>
          </button>
        </div>
      `;
    }

    if (!notificationHtml) return;

    const event = new CustomEvent("toast:show", {
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
      // Use Turbo to visit the frame's source
      foldersGridFrame.src = url.pathname + url.search;
    }
  }

  updateFileMove(uploadData) {
    if (!uploadData) return;

    const uploadId = uploadData.id;
    const newFolderId = uploadData.folder_id;
    const newFolderName = uploadData.folder_name || "No folder";

    // Find the file element using data attribute (works for both grid and list views)
    const fileElement = document.querySelector(`[data-upload-id="${uploadId}"]`);

    if (fileElement) {
      // Check if we're viewing the folder the file was moved to
      const currentFolderId = this.getCurrentFolderId();
      const stringNewFolderId = newFolderId ? String(newFolderId) : null;
      const stringCurrentFolderId = currentFolderId ? String(currentFolderId) : null;

      if (stringNewFolderId && stringNewFolderId !== stringCurrentFolderId) {
        // File moved to a different folder - remove it from view with animation
        fileElement.style.transition = 'opacity 0.3s, transform 0.3s';
        fileElement.style.opacity = '0';
        fileElement.style.transform = 'translateX(-20px)';

        setTimeout(() => {
          fileElement.remove();
          this.updateFileCountsAfterMove(uploadId, stringCurrentFolderId, stringNewFolderId);
          this.checkEmptyState();
        }, 300);
      } else {
        // File moved within the same folder or to "No folder" - update folder display
        const folderDisplay = fileElement.querySelector('[data-folder-name]');
        if (folderDisplay) {
          folderDisplay.textContent = newFolderName;
          // Update the data attribute too
          folderDisplay.setAttribute('data-folder-name', newFolderName);
        }
      }
    }

    // Refresh folders grid to update file counts
    this.refreshFoldersGrid();
  }

  getCurrentFolderId() {
    // Try to get current folder ID from URL
    const url = new URL(window.location);
    const pathParts = url.pathname.split('/');
    const folderIndex = pathParts.indexOf('folders');

    if (folderIndex !== -1 && pathParts[folderIndex + 1] && pathParts[folderIndex + 1] !== 'all') {
      return pathParts[folderIndex + 1];
    }

    return null;
  }

  updateFileCountsAfterMove(uploadId, fromFolderId, toFolderId) {
    // Update file counts in folder cards immediately for visual feedback
    // The refreshFoldersGrid will also update them, but this gives instant feedback
    const foldersGrid = document.querySelector('turbo-frame#folders_grid');
    const folderContent = document.querySelector('turbo-frame#folder_content');

    // Check both the main folders grid and the folder content (for subfolders)
    const containers = [foldersGrid, folderContent].filter(Boolean);

    containers.forEach(container => {
      const folderCards = container.querySelectorAll('[data-folder-card-id]');

      folderCards.forEach(card => {
        const folderCardId = card.getAttribute('data-folder-card-id');
        const countElement = card.querySelector('[data-folder-file-count]');

        if (countElement && folderCardId) {
          // Parse the count text (format: "5 files" or just "5")
          const countText = countElement.textContent.trim();
          const match = countText.match(/^(\d+)/);
          const currentCount = match ? parseInt(match[1]) : 0;

          // If this is the source folder, decrement count
          if (fromFolderId && folderCardId === fromFolderId) {
            const filesText = countText.includes('files') ? ' files' : '';
            countElement.textContent = `${Math.max(0, currentCount - 1)}${filesText}`;
            // Also update parent folders recursively
            this.updateParentFolderCounts(folderCardId, -1, container);
          }
          // If this is the destination folder, increment count
          if (toFolderId && folderCardId === toFolderId) {
            const filesText = countText.includes('files') ? ' files' : '';
            countElement.textContent = `${currentCount + 1}${filesText}`;
            // Also update parent folders recursively
            this.updateParentFolderCounts(folderCardId, 1, container);
          }
        }
      });
    });

    // Also refresh the folders grid to get accurate counts from the server
    this.refreshFoldersGrid();

    // If we're viewing a folder, also refresh the folder content to update subfolder counts
    if (folderContent) {
      const url = new URL(window.location);
      folderContent.src = url.pathname + url.search;
    }
  }

  updateParentFolderCounts(folderId, delta, container) {
    // This is a simplified approach - in a real scenario, we'd need to know the folder hierarchy
    // For now, we'll rely on refreshFoldersGrid to update all counts from the server
    // The recursive file_count method will calculate correctly on the server side
  }

  checkEmptyState() {
    // Check if we need to show empty state after removing files
    const filesContainer = document.querySelector('.p-5');
    if (!filesContainer) return;

    const gridView = filesContainer.querySelector('.grid');
    const listView = filesContainer.querySelector('table tbody');

    const hasFiles = (gridView && gridView.children.length > 0) ||
      (listView && listView.children.length > 0);

    if (!hasFiles) {
      // Show empty state
      const emptyState = filesContainer.querySelector('.text-center.py-12');
      if (!emptyState) {
        filesContainer.innerHTML = `
          <div class="text-center py-12">
            <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewbox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
            </svg>
            <h3 class="mt-2 text-sm font-medium text-gray-900">No files</h3>
            <p class="mt-1 text-sm text-gray-500">No files found in this folder.</p>
          </div>
        `;
      }
    }
  }


  updateCapaDocumentsTable(upload, capaId) {
    const tbody = document.getElementById('capa-documents-tbody');
    if (!tbody) return;

    // Check if empty state row exists
    const emptyRow = tbody.querySelector('tr[colspan="6"]') || tbody.querySelector('tr:only-child');
    const isEmpty = emptyRow && emptyRow.querySelector('td[colspan="6"]');

    // Get file type from mime_type
    const fileType = upload.mime_type ? upload.mime_type.split('/').pop().toUpperCase() : 'N/A';

    // Get display name (prefer name, fallback to filename)
    const displayName = upload.name || upload.filename || 'Untitled';

    // Format date if needed
    let formattedDate = upload.created_at;
    if (upload.created_at && typeof upload.created_at === 'string') {
      try {
        const date = new Date(upload.created_at);
        formattedDate = date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
      } catch (e) {
        // Keep original if parsing fails
      }
    }

    // Create new row
    const newRow = document.createElement('tr');
    newRow.setAttribute('data-upload-id', upload.id);
    newRow.innerHTML = `
      <td class="p-4">
        <span class="text-sm text-[#0D1120]">${displayName}</span>
      </td>
      <td class="p-4">
        <span class="text-sm text-[#797C81]">${fileType}</span>
      </td>
      <td class="p-4">
        <span class="text-sm text-[#797C81]">User</span>
      </td>
      <td class="p-4">
        <span class="text-sm text-[#797C81]">${formattedDate}</span>
      </td>
      <td class="p-4">
        <span class="text-sm text-[#797C81]">${upload.notes || '-'}</span>
      </td>
      <td class="p-4 text-right">
        <div class="flex items-center justify-end gap-3">
          <a href="${upload.file_url}" target="_blank" class="text-[#5C3984] hover:text-[#4A2F6B] transition-colors">
            <svg class="w-5 h-5 inline" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"></path>
            </svg>
          </a>
          <button 
            type="button" 
            class="text-red-600 hover:text-red-700 unlink-document-button" 
            title="Remove"
            data-capa-id="${capaId}"
            data-upload-id="${upload.id}"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
            </svg>
          </button>
        </div>
      </td>
    `;

    // Remove empty state row if it exists
    if (isEmpty) {
      tbody.innerHTML = '';
    }

    // Insert new row at the top
    tbody.insertBefore(newRow, tbody.firstChild);

    // Re-initialize unlink buttons to attach event listeners to the new button
    document.dispatchEvent(new CustomEvent('capa:reinit-unlink-buttons'));
  }
}
