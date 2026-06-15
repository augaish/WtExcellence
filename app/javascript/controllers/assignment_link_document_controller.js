import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="assignment-link-document"
export default class extends Controller {
  static targets = []

  connect() {
    this.assignmentId = this.element.dataset.assignmentId || this.element.dataset.capaId
    this.linkEndpoint =
      this.element.dataset.linkEndpoint ||
      (this.assignmentId ? `/assignments/${this.assignmentId}/link_documents` : null)
    this.unlinkTemplate =
      this.element.dataset.unlinkEndpointTemplate ||
      (this.assignmentId ? `/assignments/${this.assignmentId}/unlink_document/:upload_id` : null)

    this.selectedDocumentIds = new Set()
    this.allFolders = []
    this.currentSubfolders = []
    this.allDocuments = []
    this.filteredDocuments = []
    this.currentFolderId = null
    this.folderPath = [] // Track folder hierarchy: [{id, name}, ...]
    this.currentView = "list"
    this.searchQuery = ""




    const observer = new MutationObserver((mutations) => {
        mutations.forEach((mutation) => {
            if (mutation.type === "attributes" && mutation.attributeName === "open") {
                if (this.element.open) {
                    this.loadFolders()
                } else {
                    this.resetModalState()
                }
            }
        })
    })
    observer.observe(this.element, { attributes: true, attributeFilter: ["open"] })
  }


  disconnect() {
    // TODO: cleanup observers / event listeners
  }

  handleModalOpen() {
    // TODO: load folders/documents only once when modal opens
    // TODO: reset transient UI state
  }

  handleModalClose() {
    // TODO: clear selections + hide dialog if needed
  }

  resetModalState() {
    // Reset state variables
    this.selectedDocumentIds.clear()
    this.currentFolderId = null
    this.folderPath = []
    this.currentSubfolders = []
    this.searchQuery = ""
    this.currentView = "list"
    this.allDocuments = []
    this.filteredDocuments = []

    // Reset UI - show folder view, hide document view
    const folderView = document.getElementById("link_document_folder_view")
    const documentView = document.getElementById("link_document_document_view")
    if (folderView) folderView.classList.remove("hidden")
    if (documentView) documentView.classList.add("hidden")

    // Clear search inputs
    const searchInput = document.getElementById("link_document_search")
    const searchInputDoc = document.getElementById("link_document_search_document_view")
    if (searchInput) searchInput.value = ""
    if (searchInputDoc) searchInputDoc.value = ""

    // Clear document views
    this.clearDocumentViews()

    // Reset submit button and selection count
    this.updateSubmitButton()

    // Reset folder name and back button text
    const titleEl = document.getElementById("link_document_current_folder_name")
    const backLabel = document.getElementById("link_document_back_text")
    if (titleEl) titleEl.textContent = ""
    if (backLabel) backLabel.textContent = "View All Files"

    // Uncheck all checkboxes
    document.querySelectorAll(".document-checkbox").forEach(checkbox => {
      checkbox.checked = false
    })
  }

  async loadFolders() {
    const foldersGrid = document.getElementById("link_document_folders_grid")
    const loadingEl = document.getElementById("link_document_folders_loading")
    const emptyEl = document.getElementById("link_document_folders_empty")

    if (loadingEl) loadingEl.classList.remove("hidden")
    if (emptyEl) emptyEl.classList.add("hidden")

    try {
      const response = await fetch("/api/folders", {
        method: "GET",
        headers: {
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest",
        },
      })

      if (!response.ok) {
        throw new Error(`Unexpected status: ${response.status}`)
      }

      const payload = await response.json()
      this.allFolders = Array.isArray(payload?.folders) ? payload.folders : []

      if (typeof this.renderFolders === "function") {
        this.renderFolders()
      } else if (foldersGrid) {
        foldersGrid.innerHTML = this.allFolders
          .map(folder => `<div class="border border-[#E3E3E3] rounded-lg p-4">
              <p class="text-sm font-semibold text-[#0D1120]">${folder.name || "Untitled folder"}</p>
              <p class="text-xs text-gray-500 mt-1">${folder.description || ""}</p>
            </div>`)
          .join("")
      }
    } catch (error) {
      console.error("Failed to load folders for assignment link dialog:", error)
      if (typeof this.showError === "function") {
        this.showError("Unable to load folders. Please try again.")
      }
      if (emptyEl) emptyEl.classList.remove("hidden")
    } finally {
      if (loadingEl) loadingEl.classList.add("hidden")
      if ((!this.allFolders || this.allFolders.length === 0) && emptyEl) {
        emptyEl.classList.remove("hidden")
      }
    }
  }

  renderFolders() {
    const foldersGrid = document.getElementById("link_document_folders_grid")
    const emptyEl = document.getElementById("link_document_folders_empty")
    
    if (!foldersGrid) return

    // Clear existing content (except loading/empty states)
    const loadingEl = document.getElementById("link_document_folders_loading")
    if (loadingEl) loadingEl.remove()
    
    // Clear all existing folder cards
    foldersGrid.innerHTML = ""
    
    // Filter folders based on search
    let foldersToShow = this.allFolders
    if (this.searchQuery) {
      const query = this.searchQuery.toLowerCase()
      foldersToShow = this.allFolders.filter(folder => 
        folder.name.toLowerCase().includes(query) ||
        (folder.description && folder.description.toLowerCase().includes(query))
      )
    }

    if (foldersToShow.length === 0) {
      if (emptyEl) emptyEl.classList.remove("hidden")
      return
    }

    if (emptyEl) emptyEl.classList.add("hidden")

    // Add "All Documents" card
    const allDocumentsCard = this.createFolderCard({
      id: "all",
      name: "All Documents",
      description: "View all documents",
      file_count: 0,
      updated_at: ""
    }, true)
    foldersGrid.appendChild(allDocumentsCard)

    // Add folder cards
    foldersToShow.forEach(folder => {
      const card = this.createFolderCard(folder, false)
      foldersGrid.appendChild(card)
    })
  }

  createFolderCard(folder, isAllDocuments = false) {
    const card = document.createElement("div")
    const folderColor = folder.color || "#5C3984"
    const borderStyle = isAllDocuments ? "" : `border-left: 4px solid ${folderColor};`
    card.className = "bg-[#FFFFFF] rounded-lg px-4 pt-4 pb-3 border border-[#E3E3E3] hover:shadow-lg transition-shadow duration-200 h-full flex flex-col relative cursor-pointer"
    if (borderStyle) {
      card.style.cssText = borderStyle
    }
    card.dataset.folderId = folder.id

    const fileCount = isAllDocuments ? "All" : folder.file_count || 0
    const filesText = fileCount === "All" ? "files" : (fileCount === 1 ? "file" : "files")
    const updatedDate = folder.updated_at ? folder.updated_at : ""

    card.innerHTML = `
      <div class="flex-1">
        <h3 class="text-lg font-semibold text-[#0D1120] mb-2 ${isAllDocuments ? "pr-8" : "pr-12"}">${this.escapeHtml(folder.name)}</h3>
        <p class="text-sm text-gray-600 mb-4">${this.escapeHtml(folder.description || "")}</p>
        <div class="flex items-center gap-2 ${updatedDate ? "mb-3" : "mb-4"}">
          <svg class="w-5 h-5 text-[#5C3984]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
          </svg>
          <span class="text-sm font-medium text-[#0D1120]">${fileCount} ${filesText}</span>
        </div>
        ${updatedDate ? `
        <div class="flex items-center gap-2 mb-4">
          <svg class="w-4 h-4 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"></path>
          </svg>
          <span class="text-xs text-gray-500">Updated ${updatedDate}</span>
        </div>
        ` : ""}
      </div>
      <div class="flex items-center justify-between space-x-2 mt-auto">
        <button type="button" class="flex-1 flex items-center justify-center w-full bg-[#D6C4ED] hover:bg-[#CEBCE5] text-[#0D1120] px-4 py-2 rounded-lg font-medium transition-colors duration-200">
          <span>Open</span>
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
          </svg>
        </button>
        <div class="w-5"></div>
      </div>
    `

    // Handle card click - open folder when clicking anywhere on the card
    card.addEventListener("click", (e) => {
      // Don't prevent default if clicking the button (let it handle its own click)
      if (!e.target.closest("button")) {
        this.openFolder(folder.id, folder.name)
      }
    })

    // Handle button click
    const button = card.querySelector("button")
    if (button) {
      button.addEventListener("click", (e) => {
        e.stopPropagation()
        this.openFolder(folder.id, folder.name)
      })
    }

    return card
  }

  async openFolder(folderId, folderName) {
    // Check if we're navigating to a subfolder (not going back)
    // If currentFolderId is set and matches a parent in the path, we're navigating forward
    const isNavigatingForward = !this.currentFolderId || 
                                 this.folderPath.length === 0 || 
                                 this.folderPath[this.folderPath.length - 1].id !== folderId
    
    if (isNavigatingForward) {
      // Add to folder path only if navigating forward
      this.folderPath.push({ id: folderId, name: folderName })
    }
    
    this.currentFolderId = folderId

    const folderView = document.getElementById("link_document_folder_view")
    const documentView = document.getElementById("link_document_document_view")
    const folderNameEl = document.getElementById("link_document_current_folder_name")
    const backTextEl = document.getElementById("link_document_back_text")

    if (folderView) folderView.classList.add("hidden")
    if (documentView) documentView.classList.remove("hidden")
    if (folderNameEl) folderNameEl.textContent = folderName || "All Documents"
    
    // Update back button text based on folder path
    if (backTextEl) {
      if (this.folderPath.length > 1) {
        // Show parent folder name
        const parentFolder = this.folderPath[this.folderPath.length - 2]
        backTextEl.textContent = parentFolder.name
      } else {
        backTextEl.textContent = "View All Files"
      }
    }

    // Load folder details including subfolders
    await this.loadFolderDetails(folderId)
    await this.loadDocuments(folderId === "all" ? null : folderId)
  }

  async loadFolderDetails(folderId) {
    if (!folderId || folderId === "all") {
      this.currentSubfolders = []
      this.renderSubfolders()
      return
    }
    
    try {
      const response = await fetch(`/api/folders/${folderId}`, {
        method: "GET",
        headers: {
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest"
        }
      })

      if (response.ok) {
        const data = await response.json()
        this.currentSubfolders = data.subfolders || []
        this.renderSubfolders()
      } else {
        this.currentSubfolders = []
        this.renderSubfolders()
      }
    } catch (error) {
      console.error("Error loading folder details:", error)
      this.currentSubfolders = []
      this.renderSubfolders()
    }
  }

  renderSubfolders() {
    const subfoldersSection = document.getElementById("link_document_subfolders_section")
    const subfoldersGrid = document.getElementById("link_document_subfolders_grid")
    
    if (!subfoldersSection || !subfoldersGrid) return
    
    // Always clear existing subfolders first
    subfoldersGrid.innerHTML = ""
    
    // Filter subfolders based on search
    let subfoldersToShow = this.currentSubfolders
    if (this.searchQuery) {
      const query = this.searchQuery.toLowerCase()
      subfoldersToShow = this.currentSubfolders.filter(subfolder => 
        subfolder.name.toLowerCase().includes(query) ||
        (subfolder.description && subfolder.description.toLowerCase().includes(query))
      )
    }
    
    if (subfoldersToShow.length === 0) {
      subfoldersSection.classList.add("hidden")
      return
    }
    
    subfoldersSection.classList.remove("hidden")
    
    subfoldersToShow.forEach(subfolder => {
      const card = this.createFolderCard(subfolder, false)
      subfoldersGrid.appendChild(card)
    })
  }

  goBackToFolders() {
    // Remove current folder from path
    if (this.folderPath.length > 0) {
      this.folderPath.pop()
    }
    
    // If there's a parent folder, navigate to it
    if (this.folderPath.length > 0) {
      const parentFolder = this.folderPath[this.folderPath.length - 1]
      this.currentFolderId = parentFolder.id
      this.loadFolderDetails(parentFolder.id)
      this.loadDocuments(parentFolder.id)
      
      const folderNameEl = document.getElementById("link_document_current_folder_name")
      const backTextEl = document.getElementById("link_document_back_text")
      
      if (folderNameEl) folderNameEl.textContent = parentFolder.name
      
      // Update back button text
      if (backTextEl) {
        if (this.folderPath.length > 1) {
          const grandParentFolder = this.folderPath[this.folderPath.length - 2]
          backTextEl.textContent = grandParentFolder.name
        } else {
          backTextEl.textContent = "View All Files"
        }
      }
    } else {
      // Go back to root folder view
      this.currentFolderId = null
      this.selectedDocumentIds.clear()
      this.currentSubfolders = []
      this.updateSubmitButton()
      
      const folderView = document.getElementById("link_document_folder_view")
      const documentView = document.getElementById("link_document_document_view")
      const backTextEl = document.getElementById("link_document_back_text")

      if (folderView) folderView.classList.remove("hidden")
      if (documentView) documentView.classList.add("hidden")
      if (backTextEl) backTextEl.textContent = "View All Files"

      // Clear document views
      this.clearDocumentViews()
      this.renderSubfolders()
    }
  }

  async loadDocuments(folderId = null) {
    const loadingEl = document.getElementById("link_document_documents_loading")
    const emptyEl = document.getElementById("link_document_documents_empty")
    if (loadingEl) loadingEl.classList.remove("hidden")
    if (emptyEl) emptyEl.classList.add("hidden")

    try {
      const url =
        folderId && folderId !== "all"
          ? `/api/documents?folder_id=${encodeURIComponent(folderId)}`
          : "/api/documents"

      const response = await fetch(url, {
        method: "GET",
        headers: {
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest",
        },
      })

      if (!response.ok) {
        throw new Error(`Unable to fetch documents (${response.status})`)
      }

      const payload = await response.json()
      this.allDocuments = Array.isArray(payload?.documents) ? payload.documents : []
      this.filterDocuments()
    } catch (error) {
      console.error("Failed to load documents for assignment dialog:", error)
      this.showError("Unable to load documents. Please try again.")
      if (emptyEl) emptyEl.classList.remove("hidden")
    } finally {
      if (loadingEl) loadingEl.classList.add("hidden")
      if ((!this.allDocuments || this.allDocuments.length === 0) && emptyEl) {
        emptyEl.classList.remove("hidden")
      }
    }
  }

  filterDocuments() {
    let filtered = this.allDocuments

    // Apply search filter
    if (this.searchQuery) {
      const query = this.searchQuery.toLowerCase()
      filtered = filtered.filter(doc => 
        (doc.display_name && doc.display_name.toLowerCase().includes(query)) ||
        (doc.name && doc.name.toLowerCase().includes(query)) ||
        (doc.notes && doc.notes.toLowerCase().includes(query))
      )
    }

    this.filteredDocuments = filtered
    this.renderDocuments()
  }

  renderDocuments() {
    const listView = document.getElementById("link_document_documents_list")
    const gridView = document.getElementById("link_document_documents_grid")
    const emptyEl = document.getElementById("link_document_documents_empty")
    const listTbody = document.getElementById("link_document_documents_list_tbody")

    if (this.filteredDocuments.length === 0) {
      if (listView) listView.classList.add("hidden")
      if (gridView) gridView.innerHTML = ""
      if (emptyEl) emptyEl.classList.remove("hidden")
      return
    }

    if (emptyEl) emptyEl.classList.add("hidden")

    if (this.currentView === "list") {
      this.renderDocumentsList(listTbody)
      if (listView) listView.classList.remove("hidden")
      if (gridView) gridView.innerHTML = ""
    } else {
      this.renderDocumentsGrid(gridView)
      if (listView) listView.classList.add("hidden")
    }
  }

  renderDocumentsList(tbody) {
    if (!tbody) return
    tbody.innerHTML = ""

    this.filteredDocuments.forEach(doc => {
      const row = this.createDocumentListRow(doc)
      tbody.appendChild(row)
    })
  }

  createDocumentListRow(doc) {
    const row = document.createElement("tr")
    row.className = "border-b border-gray-100 bg-white hover:bg-gray-50 transition-colors"
    row.dataset.uploadId = doc.id

    const isSelected = this.selectedDocumentIds.has(doc.id.toString())
    const fileType = this.getFileType(doc.mime_type)
    const typeClass = this.getFileTypeClass(fileType)

    row.innerHTML = `
      <td class="py-4 px-4">
        <input 
          type="checkbox" 
          class="document-checkbox rounded border-gray-300 text-[#5C3984] focus:ring-[#5C3984]"
          data-upload-id="${doc.id}"
          ${isSelected ? "checked" : ""}
          data-action="change->assignment-link-document#toggleDocument"
        />
      </td>
      <td class="py-4 px-4">
        <div class="flex flex-col">
          <span class="font-semibold text-[#0D1120] text-sm">${this.escapeHtml(doc.display_name || doc.name || "Untitled")}</span>
          ${doc.notes ? `<span class="text-xs text-gray-500 mt-1 truncate max-w-xs">${this.escapeHtml(doc.notes)}</span>` : ""}
        </div>
      </td>
      <td class="py-4 px-4">
        <span class="px-2 py-1 rounded-md text-xs font-medium ${typeClass}">${fileType}</span>
      </td>
      <td class="py-4 px-4">
        <span class="text-sm text-gray-700">${doc.created_at || "-"}</span>
      </td>
    `

    return row
  }

  renderDocumentsGrid(gridContainer) {
    if (!gridContainer) return
    gridContainer.innerHTML = ""

    this.filteredDocuments.forEach(doc => {
      const card = this.createDocumentGridCard(doc)
      gridContainer.appendChild(card)
    })
  }

  createDocumentGridCard(doc) {
    const card = document.createElement("div")
    card.className = "bg-white rounded-lg p-4 border border-gray-200 hover:shadow-lg transition-all duration-200"
    card.dataset.uploadId = doc.id

    const isSelected = this.selectedDocumentIds.has(doc.id.toString())
    const fileType = this.getFileType(doc.mime_type)
    const typeClass = this.getFileTypeClass(fileType)

    card.innerHTML = `
      <div class="flex items-center justify-between mb-3">
        <div class="flex items-center gap-2">
          <input 
            type="checkbox" 
            class="document-checkbox rounded border-gray-300 text-[#5C3984] focus:ring-[#5C3984]"
            data-upload-id="${doc.id}"
            ${isSelected ? "checked" : ""}
            data-action="change->assignment-link-document#toggleDocument"
          />
          <span class="px-2 py-1 rounded-md text-xs font-medium ${typeClass}">${fileType}</span>
        </div>
      </div>
      <h4 class="font-semibold text-gray-900 text-sm mb-2 line-clamp-1">${this.escapeHtml(doc.display_name || doc.name || "Untitled")}</h4>
      ${doc.notes ? `<p class="text-xs text-gray-500 mb-4 line-clamp-2">${this.escapeHtml(doc.notes)}</p>` : "<p class=\"text-xs text-gray-500 mb-4\"></p>"}
      <div class="flex items-center gap-2 mb-2">
        <span class="text-xs text-gray-600">${doc.created_at || "-"}</span>
      </div>
    `

    return card
  }

  toggleDocument(event) {
    const checkbox = event.target
    const uploadId = checkbox.dataset.uploadId
    if (!uploadId) return

    if (checkbox.checked) {
      this.selectedDocumentIds.add(uploadId)
    } else {
      this.selectedDocumentIds.delete(uploadId)
    }
    this.updateSubmitButton()
  }

  toggleSelectAll(event) {
    const checked = event.target.checked
    document.querySelectorAll(".document-checkbox").forEach(input => {
      input.checked = checked
      const id = input.dataset.uploadId
      if (!id) return
      if (checked) {
        this.selectedDocumentIds.add(id)
      } else {
        this.selectedDocumentIds.delete(id)
      }
    })
    this.updateSubmitButton()
    this.renderDocuments() // Re-render to update checkboxes
  }

  switchToListView() {
    this.currentView = "list"
    const listBtn = document.getElementById("link_document_view_list")
    const gridBtn = document.getElementById("link_document_view_grid")
    
    if (listBtn) {
      listBtn.className = "px-4 py-2 rounded-md text-sm font-medium transition-colors bg-[#5C3984] text-white"
    }
    if (gridBtn) {
      gridBtn.className = "px-4 py-2 rounded-md text-sm font-medium transition-colors text-gray-600 hover:text-gray-900"
    }
    
    this.renderDocuments()
  }

  switchToGridView() {
    this.currentView = "grid"
    const listBtn = document.getElementById("link_document_view_list")
    const gridBtn = document.getElementById("link_document_view_grid")
    
    if (listBtn) {
      listBtn.className = "px-4 py-2 rounded-md text-sm font-medium transition-colors text-gray-600 hover:text-gray-900"
    }
    if (gridBtn) {
      gridBtn.className = "px-4 py-2 rounded-md text-sm font-medium transition-colors bg-[#5C3984] text-white"
    }
    
    this.renderDocuments()
  }

  updateSubmitButton() {
    const submitBtn = document.getElementById("link_document_submit")
    const counter = document.getElementById("link_document_submit_count")
    const counterValue = document.getElementById("link_document_submit_count_value")
    const selectionBadge = document.getElementById("link_document_selected_count")

    const count = this.selectedDocumentIds.size
    if (submitBtn) submitBtn.disabled = count === 0
    if (counterValue) counterValue.textContent = count
    if (counter) counter.classList.toggle("hidden", count === 0)
    if (selectionBadge) {
      selectionBadge.textContent = `${count} selected`
      selectionBadge.classList.toggle("hidden", count === 0)
    }
  }

  async handleSubmit(event) {
    event.preventDefault()
    if (!this.linkEndpoint) {
      this.showError("Missing assignment link endpoint.")
      return
    }
    if (this.selectedDocumentIds.size === 0) return

    const submitBtn = document.getElementById("link_document_submit")
    const originalLabel = submitBtn ? submitBtn.innerHTML : ""
    if (submitBtn) {
      submitBtn.disabled = true
      submitBtn.textContent = "Linking…"
    }

    try {
      const payload = { upload_ids: Array.from(this.selectedDocumentIds) }
      const checklistItemId = this.checklistItemId || this.element.dataset.checklistItemId
      if (checklistItemId) payload.checklist_item_id = checklistItemId

      const response = await fetch(this.linkEndpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "",
        },
        body: JSON.stringify(payload),
      })

      if (!response.ok) {
        throw new Error(`Link request failed (${response.status})`)
      }

      const result = await response.json()

      // Update the assignment evidence list with newly linked documents
      if (result.documents && result.documents.length > 0) {
        result.documents.forEach(doc => {
          this.updateDocumentsTable(doc)
        })
      }

      // Show success notification
      if (result.notification_html) {
        const event = new CustomEvent('toast:show', {
          detail: { notificationHtml: result.notification_html },
          bubbles: true
        })
        document.dispatchEvent(event)
      }
      
      // Close modal after a short delay to allow DOM updates
      setTimeout(() => {
        this.closeModalAndReset()
      }, 100)
    } catch (error) {
      console.error("Failed to link documents:", error)
      this.showError("Unable to link documents. Please try again.")
    } finally {
      if (submitBtn) {
        submitBtn.disabled = false
        submitBtn.innerHTML = originalLabel
      }
    }
  }

  closeModalAndReset() {
    this.selectedDocumentIds.clear()
    this.updateSubmitButton()
    this.clearDocumentViews()
    this.resetModalState()
    
    // Close modal using basic-modal controller
    const dialog = document.getElementById('link_document_dialog')
    if (dialog) {
      // Try to get the basic-modal controller and close it
      const application = window.Stimulus
      if (application) {
        const controller = application.getControllerForElementAndIdentifier(dialog, 'basic-modal')
        if (controller && typeof controller.close === 'function') {
          // Create a fake event object for the close method
          const fakeEvent = { preventDefault: () => {}, currentTarget: dialog }
          controller.close(fakeEvent)
        } else {
          // Fallback: close dialog directly
          if (typeof dialog.close === 'function') {
            dialog.close()
          } else {
            dialog.style.display = 'none'
          }
        }
      } else {
        // Fallback: close dialog directly
        if (typeof dialog.close === 'function') {
          dialog.close()
        } else {
          dialog.style.display = 'none'
        }
      }
    }
  }

  clearDocumentViews() {
    const listBody = document.getElementById("link_document_documents_list_tbody")
    const grid = document.getElementById("link_document_documents_grid")
    const subfoldersGrid = document.getElementById("link_document_subfolders_grid")
    const subfoldersSection = document.getElementById("link_document_subfolders_section")
    
    if (listBody) listBody.innerHTML = ""
    if (grid) grid.innerHTML = ""
    if (subfoldersGrid) subfoldersGrid.innerHTML = ""
    if (subfoldersSection) subfoldersSection.classList.add("hidden")
  }

  buildUnlinkUrl(uploadId) {
    if (!this.unlinkTemplate || !uploadId) return null
    return this.unlinkTemplate.replace(":upload_id", uploadId)
  }

  updateDocumentsTable(uploadDoc) {
    // Get or create the evidence attachments list container
    let attachmentsList = document.getElementById('evidence-attachments-list')
    const assignmentId = this.assignmentId
    
    if (!attachmentsList) {
      // Create the container if it doesn't exist
      // Find the "Link or Upload Evidence" section by looking for the heading
      const headings = Array.from(document.querySelectorAll('h2'))
      const evidenceHeading = headings.find(h2 => 
        h2.textContent && h2.textContent.trim().includes('Link or Upload Evidence')
      )
      
      if (evidenceHeading) {
        const evidenceSection = evidenceHeading.closest('.bg-white')
        if (evidenceSection) {
          attachmentsList = document.createElement('div')
          attachmentsList.id = 'evidence-attachments-list'
          const linkButton = evidenceSection.querySelector('button[data-basic-modal-dialog-value="link_document_dialog"]')
          if (linkButton && linkButton.parentElement) {
            linkButton.parentElement.insertBefore(attachmentsList, linkButton)
          } else {
            evidenceSection.insertBefore(attachmentsList, evidenceHeading.nextSibling)
          }
        } else {
          console.error('Could not find evidence section container')
          return
        }
      } else {
        console.error('Could not find "Link or Upload Evidence" heading')
        return
      }
    }

    // Check if document is already in the list
    const existingDoc = attachmentsList.querySelector(`[data-upload-id="${uploadDoc.id}"]`)
    if (existingDoc) {
      return // Document already exists, don't add duplicate
    }

    // Create the document row
    const docRow = document.createElement('div')
    docRow.className = 'flex items-center justify-between p-4 border border-[#E3E3E3] rounded-lg mb-3'
    docRow.setAttribute('data-attachment-id', uploadDoc.id) // Using upload id as attachment id for now
    docRow.setAttribute('data-upload-id', uploadDoc.id)

    const displayName = uploadDoc.display_name || uploadDoc.name || 'Uploaded document.pdf'
    const hasFile = uploadDoc.file_attached === true
    const fileUrl = uploadDoc.file_url || ''

    docRow.innerHTML = `
      <div class="flex items-center gap-3">
        <svg class="w-5 h-5 text-[#5C3984]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z"></path>
        </svg>
        <span class="text-sm text-[#0D1120]">${this.escapeHtml(displayName)}</span>
      </div>
      <div class="flex items-center gap-2">
        ${hasFile && fileUrl ? `
        <a href="${this.escapeHtml(fileUrl)}" 
           class="p-2 text-[#5C3984] hover:text-[#4A2F6B] transition-colors" 
           title="Download">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"></path>
          </svg>
        </a>
        ` : ''}
        <button type="button" 
                class="p-2 text-gray-400 hover:text-red-500 transition-colors unlink-document-btn" 
                title="Unlink"
                data-upload-id="${uploadDoc.id}"
                data-assignment-id="${assignmentId}">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l3.59 3.59m0 0A9.953 9.953 0 0112 5c4.478 0 8.268 2.943 9.543 7a10.025 10.025 0 01-4.132 5.411m0 0L21 21"></path>
          </svg>
        </button>
      </div>
    `

    // Add the row to the list (insert before the "Link or Upload Evidence" button)
    const linkButton = attachmentsList.parentElement?.querySelector('button[data-basic-modal-dialog-value="link_document_dialog"]')
    if (linkButton && linkButton.parentElement) {
      linkButton.parentElement.insertBefore(docRow, linkButton)
    } else {
      // If button not found, append to the list
      attachmentsList.appendChild(docRow)
    }

    // Ensure the attachments list container is visible
    attachmentsList.style.display = 'block'
  }

  handleSearch(event) {
    this.searchQuery = event.target.value
    
    // Sync search query across both search inputs
    const searchInput = document.getElementById("link_document_search")
    const searchInputDoc = document.getElementById("link_document_search_document_view")
    if (event.target.id === "link_document_search" && searchInputDoc) {
      searchInputDoc.value = this.searchQuery
    } else if (event.target.id === "link_document_search_document_view" && searchInput) {
      searchInput.value = this.searchQuery
    }

    // If we're in folder view, filter folders
    const folderView = document.getElementById("link_document_folder_view")
    if (folderView && !folderView.classList.contains("hidden")) {
      this.renderFolders()
    } else {
      // If we're in document view, filter documents and subfolders
      this.filterDocuments()
      this.renderSubfolders()
    }
  }

  getFileType(mimeType) {
    if (!mimeType) return "File"
    
    if (mimeType.includes("pdf")) return "PDF"
    if (mimeType.includes("excel") || mimeType.includes("spreadsheet") || mimeType.includes("xls")) return "Excel"
    if (mimeType.includes("word") || mimeType.includes("document") || mimeType.includes("doc")) return "Word"
    if (mimeType.includes("image")) return "Image"
    if (mimeType.includes("text")) return "Text"
    if (mimeType.includes("email") || mimeType.includes("message")) return "Email"
    return "File"
  }

  getFileTypeClass(fileType) {
    const typeClasses = {
      "PDF": "bg-red-100 text-red-800",
      "Excel": "bg-green-100 text-green-800",
      "Word": "bg-blue-100 text-blue-800",
      "Image": "bg-purple-100 text-purple-800",
      "Email": "bg-blue-100 text-blue-800",
      "Text": "bg-gray-100 text-gray-800",
      "File": "bg-gray-100 text-gray-800"
    }
    return typeClasses[fileType] || "bg-gray-100 text-gray-800"
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }

  showError(message) {
    if (window?.dispatchEvent) {
      const notificationHtml = `
        <div data-toast-target="notification"
             class="bg-[#FFF5F5] border border-[#FECACA] rounded-lg p-3 text-sm text-[#B91C1C]">
          ${message}
        </div>`
      window.dispatchEvent(new CustomEvent("toast:show", { detail: { notificationHtml } }))
    } else {
      alert(message)
    }
  }
}


