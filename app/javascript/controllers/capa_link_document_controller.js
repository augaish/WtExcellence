import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="capa-link-document"
export default class extends Controller {
  static targets = [];

  connect() {
    this.selectedDocumentIds = new Set();
    this.capaId = this.element.dataset.capaId;
    this.capaActionId = this.element.dataset.capaActionId || null;
    this.unlinkIconPath = this.element.dataset.unlinkIconPath || '/assets/unlink-icon.svg';
    this.currentFolderId = null;
    this.folderPath = []; // Track folder hierarchy: [{id, name}, ...]
    this.currentView = 'list'; // 'list' or 'grid'
    this.searchQuery = '';
    this.allFolders = [];
    this.currentSubfolders = [];
    this.allDocuments = [];
    this.filteredDocuments = [];
    this.translations = {
      selectedCount: {
        zero: this.element.dataset.selectedCountZero || '0 selected',
        one: this.element.dataset.selectedCountOne || '1 selected',
        two: this.element.dataset.selectedCountTwo || '2 selected',
        few: this.element.dataset.selectedCountFew || '%{count} selected',
        many: this.element.dataset.selectedCountMany || '%{count} selected',
        other: this.element.dataset.selectedCountOther || '%{count} selected'
      },
      linking: this.element.dataset.linkingLabel || 'Linking...',
      submitLabel: this.element.dataset.submitLabel || 'Link Document(s)',
      successFallback: this.element.dataset.linkSuccessFallback || 'Document linked successfully, but there was an issue displaying the notification.',
      successBasic: this.element.dataset.linkSuccessBasic || 'Document linked successfully',
      failed: this.element.dataset.linkFailed || 'Failed to link document. Please try again.',
      genericError: this.element.dataset.genericError || 'An error occurred. Please try again.',
      requestFailedTemplate: this.element.dataset.requestFailedTemplate || 'Request failed with status %{status}',
      allDocuments: this.element.dataset.allDocumentsLabel || 'All Documents',
      viewAllDocuments: this.element.dataset.viewAllDocumentsLabel || 'View all documents',
      filesLabel: this.element.dataset.filesLabel || 'files',
      fileLabel: this.element.dataset.fileLabel || 'file',
      updatedLabel: this.element.dataset.updatedLabel || 'Updated %{date}',
      openLabel: this.element.dataset.openLabel || 'Open',
      untitled: this.element.dataset.untitledLabel || 'Untitled',
      userLabel: this.element.dataset.userLabel || 'User',
      removeLabel: this.element.dataset.removeLabel || 'Remove',
      viewAllFilesLabel: this.element.dataset.viewAllFilesLabel || 'View All Files',
      loadFoldersFailed: this.element.dataset.loadFoldersFailed || 'Failed to load folders',
      loadFoldersError: this.element.dataset.loadFoldersError || 'Error loading folders',
      loadDocumentsFailed: this.element.dataset.loadDocumentsFailed || 'Failed to load documents',
      loadDocumentsError: this.element.dataset.loadDocumentsError || 'Error loading documents',
      mimeTypeNa: this.element.dataset.mimeNaLabel || 'N/A',
      fileTypes: {
        pdf: this.element.dataset.fileTypePdf || 'PDF',
        excel: this.element.dataset.fileTypeExcel || 'Excel',
        word: this.element.dataset.fileTypeWord || 'Word',
        image: this.element.dataset.fileTypeImage || 'Image',
        text: this.element.dataset.fileTypeText || 'Text',
        email: this.element.dataset.fileTypeEmail || 'Email',
        file: this.element.dataset.fileTypeFile || 'File'
      }
    };
    
    // Explicitly ensure dialog is closed on connect
    if (this.element.open) {
      this.element.close();
    }
    
    // Listen for modal close event - only load folders when modal is actually opened
    this.element.addEventListener('close', () => {
      this.handleModalClose();
      // Explicitly hide the dialog when close event fires
      this.element.style.display = 'none';
    });
    
    // Use a MutationObserver or listen for the 'open' attribute change
    this.observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (mutation.type === 'attributes' && mutation.attributeName === 'open') {
          if (this.element.open) {
            this.handleModalOpen();
          } else {
            this.handleModalClose();
          }
        }
      });
    });
    
    this.observer.observe(this.element, { attributes: true, attributeFilter: ['open'] });
    
    // Check if modal is already open (shouldn't be, but just in case)
    if (this.element.open) {
      this.handleModalOpen();
    }
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect();
    }
  }

  handleModalOpen() {
    // Only load folders when modal is actually opened
    if (this.allFolders.length === 0) {
      this.loadFolders();
    }
    // Reset state when opening
    this.resetModalState();
  }

  handleModalClose() {
    // Reset state when closing
    this.resetModalState();
    // Explicitly hide the dialog
    if (this.element) {
      this.element.style.display = 'none';
    }
  }

  resetModalState() {
    this.selectedDocumentIds.clear();
    this.currentFolderId = null;
    this.folderPath = [];
    this.currentSubfolders = [];
    this.searchQuery = '';
    this.currentView = 'list';
    
    // Reset UI
    const searchInput = document.getElementById('link_document_search');
    if (searchInput) searchInput.value = '';
    const searchInputDoc = document.getElementById('link_document_search_document_view');
    if (searchInputDoc) searchInputDoc.value = '';
    
    // Go back to folder view
    const folderView = document.getElementById('link_document_folder_view');
    const documentView = document.getElementById('link_document_document_view');
    
    if (folderView) folderView.classList.remove('hidden');
    if (documentView) documentView.classList.add('hidden');
    
    this.clearDocumentViews();
    this.updateSubmitButton();
  }

  async loadFolders() {
    const foldersGrid = document.getElementById('link_document_folders_grid');
    const loadingEl = document.getElementById('link_document_folders_loading');
    const emptyEl = document.getElementById('link_document_folders_empty');
    
    if (loadingEl) loadingEl.classList.remove('hidden');
    if (emptyEl) emptyEl.classList.add('hidden');

    try {
      const response = await fetch('/api/folders', {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      });

      if (response.ok) {
        const data = await response.json();
        this.allFolders = data.folders || [];
        this.renderFolders();
      } else {
        this.showError(this.translations.loadFoldersFailed);
      }
    } catch (error) {
      console.error('Error loading folders:', error);
      this.showError(this.translations.loadFoldersError);
    } finally {
      if (loadingEl) loadingEl.classList.add('hidden');
    }
  }

  renderFolders() {
    const foldersGrid = document.getElementById('link_document_folders_grid');
    const emptyEl = document.getElementById('link_document_folders_empty');
    
    if (!foldersGrid) return;

    // Clear existing content (except loading/empty states)
    const loadingEl = document.getElementById('link_document_folders_loading');
    if (loadingEl) loadingEl.remove();
    
    // Clear all existing folder cards
    foldersGrid.innerHTML = '';
    
    // Filter folders based on search
    let foldersToShow = this.allFolders;
    if (this.searchQuery) {
      const query = this.searchQuery.toLowerCase();
      foldersToShow = this.allFolders.filter(folder => 
        folder.name.toLowerCase().includes(query) ||
        (folder.description && folder.description.toLowerCase().includes(query))
      );
    }

    if (foldersToShow.length === 0) {
      if (emptyEl) emptyEl.classList.remove('hidden');
      return;
    }

    if (emptyEl) emptyEl.classList.add('hidden');

    // Add "All Documents" card
    const allDocumentsCard = this.createFolderCard({
      id: 'all',
      name: this.translations.allDocuments,
      description: this.translations.viewAllDocuments,
      file_count: 0, // Will be updated if needed
      updated_at: ''
    }, true);
    foldersGrid.appendChild(allDocumentsCard);

    // Add folder cards
    foldersToShow.forEach(folder => {
      const card = this.createFolderCard(folder, false);
      foldersGrid.appendChild(card);
    });
  }

  createFolderCard(folder, isAllDocuments = false) {
    const card = document.createElement('div');
    const folderColor = folder.color || '#5C3984';
    const borderStyle = isAllDocuments ? '' : `border-left: 4px solid ${folderColor};`;
    card.className = 'bg-[#FFFFFF] rounded-lg px-4 pt-4 pb-3 border border-[#E3E3E3] hover:shadow-lg transition-shadow duration-200 h-full flex flex-col relative cursor-pointer';
    if (borderStyle) {
      card.style.cssText = borderStyle;
    }
    card.dataset.folderId = folder.id;

    const fileCount = isAllDocuments ? null : (folder.file_count || 0);
    const fileCountLabel = isAllDocuments ? this.translations.allDocuments : `${fileCount} ${fileCount === 1 ? this.translations.fileLabel : this.translations.filesLabel}`;
    const updatedDate = folder.updated_at ? folder.updated_at : '';
    const updatedLabel = updatedDate ? this.translations.updatedLabel.replace('%{date}', updatedDate) : '';

    card.innerHTML = `
      <div class="flex-1">
        <h3 class="text-lg font-semibold text-[#0D1120] mb-2 ${isAllDocuments ? 'pr-8' : 'pr-12'}">${this.escapeHtml(folder.name)}</h3>
        <p class="text-sm text-gray-600 mb-4">${this.escapeHtml(folder.description || '')}</p>
        <div class="flex items-center gap-2 ${updatedDate ? 'mb-3' : 'mb-4'}">
          <svg class="w-5 h-5 text-[#5C3984]" fill="none" stroke="currentColor" viewbox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
          </svg>
          <span class="text-sm font-medium text-[#0D1120]">${fileCountLabel}</span>
        </div>
        ${updatedDate ? `
        <div class="flex items-center gap-2 mb-4">
          <svg class="w-4 h-4 text-gray-500" fill="none" stroke="currentColor" viewbox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"></path>
          </svg>
          <span class="text-xs text-gray-500">${updatedLabel}</span>
        </div>
        ` : ''}
      </div>
      <div class="flex items-center justify-between space-x-2 mt-auto">
        <button type="button" class="flex-1 flex items-center justify-center w-full bg-[#D6C4ED] hover:bg-[#CEBCE5] text-[#0D1120] px-4 py-2 rounded-lg font-medium transition-colors duration-200">
          <span>${this.translations.openLabel}</span>
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewbox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
          </svg>
        </button>
        <div class="w-5"></div>
      </div>
    `;

    // Handle card click - open folder when clicking anywhere on the card
    card.addEventListener('click', (e) => {
      // Don't prevent default if clicking the button (let it handle its own click)
      if (!e.target.closest('button')) {
        this.openFolder(folder.id, folder.name);
      }
    });

    // Handle button click
    const button = card.querySelector('button');
    if (button) {
      button.addEventListener('click', (e) => {
        e.stopPropagation();
        this.openFolder(folder.id, folder.name);
      });
    }

    return card;
  }

  async openFolder(folderId, folderName) {
    // Check if we're navigating to a subfolder (not going back)
    // If currentFolderId is set and matches a parent in the path, we're navigating forward
    const isNavigatingForward = !this.currentFolderId || 
                                 this.folderPath.length === 0 || 
                                 this.folderPath[this.folderPath.length - 1].id !== folderId;
    
    if (isNavigatingForward) {
      // Add to folder path only if navigating forward
      this.folderPath.push({ id: folderId, name: folderName });
    }
    
    this.currentFolderId = folderId;
    
    const folderView = document.getElementById('link_document_folder_view');
    const documentView = document.getElementById('link_document_document_view');
    const folderNameEl = document.getElementById('link_document_current_folder_name');
    const backTextEl = document.getElementById('link_document_back_text');

    if (folderView) folderView.classList.add('hidden');
    if (documentView) documentView.classList.remove('hidden');
    if (folderNameEl) folderNameEl.textContent = folderName || this.translations.allDocuments;
    
    // Update back button text based on folder path
    if (backTextEl) {
      if (this.folderPath.length > 1) {
        // Show parent folder name
        const parentFolder = this.folderPath[this.folderPath.length - 2];
        backTextEl.textContent = parentFolder.name;
      } else {
        backTextEl.textContent = this.translations.viewAllFilesLabel;
      }
    }

    // Load folder details including subfolders
    await this.loadFolderDetails(folderId);
    await this.loadDocuments(folderId);
  }
  
  async loadFolderDetails(folderId) {
    if (!folderId || folderId === 'all') {
      this.currentSubfolders = [];
      this.renderSubfolders();
      return;
    }
    
    try {
      const response = await fetch(`/api/folders/${folderId}`, {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      });

      if (response.ok) {
        const data = await response.json();
        this.currentSubfolders = data.subfolders || [];
        this.renderSubfolders();
      } else {
        this.currentSubfolders = [];
        this.renderSubfolders();
      }
    } catch (error) {
      console.error('Error loading folder details:', error);
      this.currentSubfolders = [];
      this.renderSubfolders();
    }
  }
  
  renderSubfolders() {
    const subfoldersSection = document.getElementById('link_document_subfolders_section');
    const subfoldersGrid = document.getElementById('link_document_subfolders_grid');
    
    if (!subfoldersSection || !subfoldersGrid) return;
    
    // Always clear existing subfolders first
    subfoldersGrid.innerHTML = '';
    
    // Filter subfolders based on search
    let subfoldersToShow = this.currentSubfolders;
    if (this.searchQuery) {
      const query = this.searchQuery.toLowerCase();
      subfoldersToShow = this.currentSubfolders.filter(subfolder => 
        subfolder.name.toLowerCase().includes(query) ||
        (subfolder.description && subfolder.description.toLowerCase().includes(query))
      );
    }
    
    if (subfoldersToShow.length === 0) {
      subfoldersSection.classList.add('hidden');
      return;
    }
    
    subfoldersSection.classList.remove('hidden');
    
    subfoldersToShow.forEach(subfolder => {
      const card = this.createFolderCard(subfolder, false);
      subfoldersGrid.appendChild(card);
    });
  }

  goBackToFolders() {
    // Remove current folder from path
    if (this.folderPath.length > 0) {
      this.folderPath.pop();
    }
    
    // If there's a parent folder, navigate to it
    if (this.folderPath.length > 0) {
      const parentFolder = this.folderPath[this.folderPath.length - 1];
      this.currentFolderId = parentFolder.id;
      this.loadFolderDetails(parentFolder.id);
      this.loadDocuments(parentFolder.id);
      
      const folderNameEl = document.getElementById('link_document_current_folder_name');
      const backTextEl = document.getElementById('link_document_back_text');
      
      if (folderNameEl) folderNameEl.textContent = parentFolder.name;
      
      // Update back button text
      if (backTextEl) {
        if (this.folderPath.length > 1) {
          const grandParentFolder = this.folderPath[this.folderPath.length - 2];
          backTextEl.textContent = grandParentFolder.name;
        } else {
          backTextEl.textContent = 'View All Files';
        }
      }
    } else {
      // Go back to root folder view
      this.currentFolderId = null;
      this.selectedDocumentIds.clear();
      this.currentSubfolders = [];
      this.updateSubmitButton();
      
      const folderView = document.getElementById('link_document_folder_view');
      const documentView = document.getElementById('link_document_document_view');
      const backTextEl = document.getElementById('link_document_back_text');

      if (folderView) folderView.classList.remove('hidden');
      if (documentView) documentView.classList.add('hidden');
      if (backTextEl) backTextEl.textContent = this.translations.viewAllFilesLabel;

      // Clear document views
      this.clearDocumentViews();
      this.renderSubfolders();
    }
  }

  async loadDocuments(folderId = null) {
    const listView = document.getElementById('link_document_documents_list');
    const gridView = document.getElementById('link_document_documents_grid');
    const loadingEl = document.getElementById('link_document_documents_loading');
    const emptyEl = document.getElementById('link_document_documents_empty');
    const listTbody = document.getElementById('link_document_documents_list_tbody');

    // Show loading
    if (listView) listView.classList.add('hidden');
    if (gridView) gridView.innerHTML = '';
    if (listTbody) listTbody.innerHTML = '';
    if (loadingEl) loadingEl.classList.remove('hidden');
    if (emptyEl) emptyEl.classList.add('hidden');

    try {
      // Handle "all" case - don't pass folder_id parameter
      const url = folderId && folderId !== 'all' && folderId !== null
        ? `/api/documents?folder_id=${folderId}`
        : '/api/documents';
      
      const response = await fetch(url, {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      });

      if (response.ok) {
        const data = await response.json();
        this.allDocuments = data.documents || [];
        this.filterDocuments();
      } else {
        this.showError(this.translations.loadDocumentsFailed);
      }
    } catch (error) {
      console.error('Error loading documents:', error);
      this.showError(this.translations.loadDocumentsError);
    } finally {
      if (loadingEl) loadingEl.classList.add('hidden');
    }
  }

  filterDocuments() {
    let filtered = this.allDocuments;

    // Apply search filter
    if (this.searchQuery) {
      const query = this.searchQuery.toLowerCase();
      filtered = filtered.filter(doc => 
        (doc.display_name && doc.display_name.toLowerCase().includes(query)) ||
        (doc.name && doc.name.toLowerCase().includes(query)) ||
        (doc.notes && doc.notes.toLowerCase().includes(query))
      );
    }

    this.filteredDocuments = filtered;
    this.renderDocuments();
  }

  renderDocuments() {
    const listView = document.getElementById('link_document_documents_list');
    const gridView = document.getElementById('link_document_documents_grid');
    const emptyEl = document.getElementById('link_document_documents_empty');
    const listTbody = document.getElementById('link_document_documents_list_tbody');

    if (this.filteredDocuments.length === 0) {
      if (listView) listView.classList.add('hidden');
      if (gridView) gridView.innerHTML = '';
      if (emptyEl) emptyEl.classList.remove('hidden');
      return;
    }

    if (emptyEl) emptyEl.classList.add('hidden');

    if (this.currentView === 'list') {
      this.renderDocumentsList(listTbody);
      if (listView) listView.classList.remove('hidden');
      if (gridView) gridView.innerHTML = '';
    } else {
      this.renderDocumentsGrid(gridView);
      if (listView) listView.classList.add('hidden');
    }
  }

  renderDocumentsList(tbody) {
    if (!tbody) return;
    tbody.innerHTML = '';

    this.filteredDocuments.forEach(doc => {
      const row = this.createDocumentListRow(doc);
      tbody.appendChild(row);
    });
  }

  createDocumentListRow(doc) {
    const row = document.createElement('tr');
    row.className = 'border-b border-gray-100 bg-white hover:bg-gray-50 transition-colors';
    row.dataset.uploadId = doc.id;

    const isSelected = this.selectedDocumentIds.has(doc.id.toString());
    const fileType = this.getFileType(doc.mime_type);
    const fileTypeLabel = this.translateFileType(fileType);
    const typeClass = this.getFileTypeClass(fileType);

    row.innerHTML = `
      <td class="py-4 px-4">
        <input 
          type="checkbox" 
          class="document-checkbox rounded border-gray-300 text-[#5C3984] focus:ring-[#5C3984]"
          data-upload-id="${doc.id}"
          ${isSelected ? 'checked' : ''}
          data-action="change->capa-link-document#toggleDocument"
        />
      </td>
      <td class="py-4 px-4">
        <div class="flex flex-col">
          <span class="font-semibold text-[#0D1120] text-sm">${this.escapeHtml(doc.display_name || doc.name || this.translations.untitled)}</span>
          ${doc.notes ? `<span class="text-xs text-gray-500 mt-1 truncate max-w-xs">${this.escapeHtml(doc.notes)}</span>` : ''}
        </div>
      </td>
      <td class="py-4 px-4">
        <span class="px-2 py-1 rounded-md text-xs font-medium ${typeClass}">${fileTypeLabel}</span>
      </td>
      <td class="py-4 px-4">
        <span class="text-sm text-gray-700">${doc.created_at || '-'}</span>
      </td>
    `;

    return row;
  }

  renderDocumentsGrid(gridContainer) {
    if (!gridContainer) return;
    gridContainer.innerHTML = '';

    this.filteredDocuments.forEach(doc => {
      const card = this.createDocumentGridCard(doc);
      gridContainer.appendChild(card);
    });
  }

  createDocumentGridCard(doc) {
    const card = document.createElement('div');
    card.className = 'bg-white rounded-lg p-4 border border-gray-200 hover:shadow-lg transition-all duration-200';
    card.dataset.uploadId = doc.id;

    const isSelected = this.selectedDocumentIds.has(doc.id.toString());
    const fileType = this.getFileType(doc.mime_type);
    const fileTypeLabel = this.translateFileType(fileType);
    const typeClass = this.getFileTypeClass(fileType);

    card.innerHTML = `
      <div class="flex items-center justify-between mb-3">
        <div class="flex items-center gap-2">
          <input 
            type="checkbox" 
            class="document-checkbox rounded border-gray-300 text-[#5C3984] focus:ring-[#5C3984]"
            data-upload-id="${doc.id}"
            ${isSelected ? 'checked' : ''}
            data-action="change->capa-link-document#toggleDocument"
          />
          <span class="px-2 py-1 rounded-md text-xs font-medium ${typeClass}">${fileTypeLabel}</span>
        </div>
      </div>
      <h4 class="font-semibold text-gray-900 text-sm mb-2 line-clamp-1">${this.escapeHtml(doc.display_name || doc.name || this.translations.untitled)}</h4>
      ${doc.notes ? `<p class="text-xs text-gray-500 mb-4 line-clamp-2">${this.escapeHtml(doc.notes)}</p>` : '<p class="text-xs text-gray-500 mb-4"></p>'}
      <div class="flex items-center gap-2 mb-2">
        <span class="text-xs text-gray-600">${doc.created_at || '-'}</span>
      </div>
    `;

    return card;
  }

  toggleDocument(event) {
    const checkbox = event.target;
    const uploadId = checkbox.dataset.uploadId;

    if (checkbox.checked) {
      this.selectedDocumentIds.add(uploadId);
    } else {
      this.selectedDocumentIds.delete(uploadId);
    }

    this.updateSubmitButton();
  }

  toggleSelectAll(event) {
    const checkbox = event.target;
    const checkboxes = document.querySelectorAll('.document-checkbox');
    
    checkboxes.forEach(cb => {
      cb.checked = checkbox.checked;
      const uploadId = cb.dataset.uploadId;
      if (checkbox.checked) {
        this.selectedDocumentIds.add(uploadId);
      } else {
        this.selectedDocumentIds.delete(uploadId);
      }
    });

    this.updateSubmitButton();
    this.renderDocuments(); // Re-render to update checkboxes
  }

  switchToListView() {
    this.currentView = 'list';
    const listBtn = document.getElementById('link_document_view_list');
    const gridBtn = document.getElementById('link_document_view_grid');
    
    if (listBtn) {
      listBtn.className = 'px-4 py-2 rounded-md text-sm font-medium transition-colors bg-[#5C3984] text-white';
    }
    if (gridBtn) {
      gridBtn.className = 'px-4 py-2 rounded-md text-sm font-medium transition-colors text-gray-600 hover:text-gray-900';
    }
    
    this.renderDocuments();
  }

  switchToGridView() {
    this.currentView = 'grid';
    const listBtn = document.getElementById('link_document_view_list');
    const gridBtn = document.getElementById('link_document_view_grid');
    
    if (listBtn) {
      listBtn.className = 'px-4 py-2 rounded-md text-sm font-medium transition-colors text-gray-600 hover:text-gray-900';
    }
    if (gridBtn) {
      gridBtn.className = 'px-4 py-2 rounded-md text-sm font-medium transition-colors bg-[#5C3984] text-white';
    }
    
    this.renderDocuments();
  }

  handleSearch(event) {
    this.searchQuery = event.target.value;
    
    // Sync search query across both search inputs
    const searchInput = document.getElementById('link_document_search');
    const searchInputDoc = document.getElementById('link_document_search_document_view');
    if (event.target.id === 'link_document_search' && searchInputDoc) {
      searchInputDoc.value = this.searchQuery;
    } else if (event.target.id === 'link_document_search_document_view' && searchInput) {
      searchInput.value = this.searchQuery;
    }
    
    // If we're in folder view, filter folders
    const folderView = document.getElementById('link_document_folder_view');
    if (folderView && !folderView.classList.contains('hidden')) {
      this.renderFolders();
    } else {
      // If we're in document view, filter documents and subfolders
      this.filterDocuments();
      this.renderSubfolders();
    }
  }

  updateSubmitButton() {
    const submitButton = document.getElementById('link_document_submit');
    const submitText = document.getElementById('link_document_submit_text');
    const submitCount = document.getElementById('link_document_submit_count');
    const submitCountValue = document.getElementById('link_document_submit_count_value');
    const selectedCountEl = document.getElementById('link_document_selected_count');

    const count = this.selectedDocumentIds.size;

    if (submitButton) {
      submitButton.disabled = count === 0;
    }

    if (submitCountValue) {
      submitCountValue.textContent = count;
    }

    if (submitCount) {
      if (count > 0) {
        submitCount.classList.remove('hidden');
      } else {
        submitCount.classList.add('hidden');
      }
    }

    if (selectedCountEl) {
      if (count > 0) {
        selectedCountEl.textContent = this.selectedCountText(count);
        selectedCountEl.classList.remove('hidden');
      } else {
        selectedCountEl.classList.add('hidden');
      }
    }
  }

  async handleSubmit(event) {
    event.preventDefault();
    event.stopPropagation();
    
    if (this.selectedDocumentIds.size === 0) return;

    const submitButton = document.getElementById('link_document_submit');
    if (submitButton) {
      if (submitButton.disabled) return;
      submitButton.disabled = true;
      submitButton.innerHTML = this.translations.linking;
    }

    try {
      const uploadIds = Array.from(this.selectedDocumentIds);
      const linkUrl = this.capaActionId
        ? `/dashboard/capa_management/${this.capaId}/capa_actions/${this.capaActionId}/link_documents`
        : `/dashboard/capa_management/${this.capaId}/link_documents`;
      const response = await fetch(linkUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({
          upload_ids: uploadIds
        })
      });

      if (response.ok) {
        let result;
        try {
          result = await response.json();
        } catch (parseError) {
          this.dispatchToast(this.translations.successFallback, 'success');
          this.closeModalAndReset();
          return;
        }
        
        // Update documents table (CAPA show page only; action page will reload)
        if (!this.capaActionId && result.documents && result.documents.length > 0) {
          result.documents.forEach(uploadDoc => {
            this.updateDocumentsTable(uploadDoc);
          });
        }

        // Show success notification
        if (result.notification_html) {
          this.dispatchToast(result.notification_html);
        } else if (result.message) {
          this.dispatchToast(result.message, 'success');
        } else {
          this.dispatchToast(this.translations.successBasic, 'success');
        }

        this.closeModalAndReset();
        if (this.capaActionId) {
          window.location.reload();
        }
      } else {
        let error;
        try {
          error = await response.json();
        } catch (parseError) {
          error = { message: this.translations.requestFailedTemplate.replace('%{status}', response.status) };
        }
        if (error.notification_html) {
          this.dispatchToast(error.notification_html);
        } else {
          this.dispatchToast(error.message || this.translations.failed, 'error');
        }
      }
    } catch (error) {
      console.error('Error linking documents:', error);
      this.dispatchToast(this.translations.genericError, 'error');
    } finally {
      if (submitButton) {
        submitButton.disabled = false;
        submitButton.innerHTML = `<span id="link_document_submit_text">${this.translations.submitLabel}</span><span id="link_document_submit_count" class="hidden"> (<span id="link_document_submit_count_value">0</span>)</span>`;
      }
    }
  }

  closeModalAndReset() {
    const dialog = this.element;
    if (dialog) {
      dialog.close();
      dialog.style.display = 'none';
    }
  }

  clearDocumentViews() {
    const listTbody = document.getElementById('link_document_documents_list_tbody');
    const gridView = document.getElementById('link_document_documents_grid');
    const subfoldersGrid = document.getElementById('link_document_subfolders_grid');
    const subfoldersSection = document.getElementById('link_document_subfolders_section');
    
    if (listTbody) listTbody.innerHTML = '';
    if (gridView) gridView.innerHTML = '';
    if (subfoldersGrid) subfoldersGrid.innerHTML = '';
    if (subfoldersSection) subfoldersSection.classList.add('hidden');
  }

  selectedCountText(count) {
    const t = this.translations.selectedCount;
    if (count === 0) return t.zero.replace('%{count}', count);
    if (count === 1) return t.one.replace('%{count}', count);
    if (count === 2) return t.two.replace('%{count}', count);
    if (count >= 3 && count <= 10) return t.few.replace('%{count}', count);
    if (count >= 11 && count <= 99) return t.many.replace('%{count}', count);
    return t.other.replace('%{count}', count);
  }

  translateFileType(type) {
    if (!type) return this.translations.fileTypes.file;
    const key = type.toLowerCase();
    return this.translations.fileTypes[key] || type;
  }

  updateDocumentsTable(uploadDoc) {
    const tbody = document.getElementById('capa-documents-tbody');
    if (!tbody) return;

    const emptyRow = tbody.querySelector('tr[colspan="6"]') || tbody.querySelector('tr:only-child');
    const isEmpty = emptyRow && emptyRow.querySelector('td[colspan="6"]');

    const fileType = uploadDoc.mime_type ? uploadDoc.mime_type.split('/').pop().toUpperCase() : this.translations.mimeTypeNa;
    const fileTypeLabel = this.translateFileType(fileType);
    const displayName = uploadDoc.display_name || uploadDoc.name || uploadDoc.filename || this.translations.untitled;

    const newRow = document.createElement('tr');
    newRow.setAttribute('data-upload-id', uploadDoc.id);
    newRow.innerHTML = `
      <td class="p-4">
        <span class="text-sm text-[#0D1120]">${this.escapeHtml(displayName)}</span>
      </td>
      <td class="p-4">
        <span class="text-sm text-[#797C81]">${fileTypeLabel}</span>
      </td>
      <td class="p-4">
        <span class="text-sm text-[#797C81]">${this.translations.userLabel}</span>
      </td>
      <td class="p-4">
        <span class="text-sm text-[#797C81]">${uploadDoc.created_at || '-'}</span>
      </td>
      <td class="p-4">
        <span class="text-sm text-[#797C81]">${this.escapeHtml(uploadDoc.notes || '-')}</span>
      </td>
      <td class="p-4 text-right">
        <div class="flex items-center justify-end gap-3">
          <a href="${uploadDoc.file_url}" target="_blank" class="text-[#5C3984] hover:text-[#4A2F6B] transition-colors">
            <svg class="w-5 h-5 inline" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"></path>
            </svg>
          </a>
          <button 
            type="button" 
            class="text-red-600 hover:text-red-700 unlink-document-button" 
            title="${this.translations.removeLabel}"
            data-capa-id="${this.capaId}"
            data-upload-id="${uploadDoc.id}"
          >
            <img src="${this.unlinkIconPath}" class="w-5 h-5" alt="${this.translations.removeLabel}" />
          </button>
        </div>
      </td>
    `;

    if (isEmpty) {
      tbody.innerHTML = '';
    }

    tbody.insertBefore(newRow, tbody.firstChild);

    // Re-initialize unlink document buttons
    const initEvent = new CustomEvent('capa:reinit-unlink-buttons', { bubbles: true });
    document.dispatchEvent(initEvent);
  }

  getFileType(mimeType) {
    if (!mimeType) return 'File';
    
    if (mimeType.includes('pdf')) return 'PDF';
    if (mimeType.includes('excel') || mimeType.includes('spreadsheet') || mimeType.includes('xls')) return 'Excel';
    if (mimeType.includes('word') || mimeType.includes('document') || mimeType.includes('doc')) return 'Word';
    if (mimeType.includes('image')) return 'Image';
    if (mimeType.includes('text')) return 'Text';
    if (mimeType.includes('email') || mimeType.includes('message')) return 'Email';
    return 'File';
  }

  getFileTypeClass(fileType) {
    const typeClasses = {
      'PDF': 'bg-red-100 text-red-800',
      'Excel': 'bg-green-100 text-green-800',
      'Word': 'bg-blue-100 text-blue-800',
      'Image': 'bg-purple-100 text-purple-800',
      'Email': 'bg-blue-100 text-blue-800',
      'Text': 'bg-gray-100 text-gray-800',
      'File': 'bg-gray-100 text-gray-800'
    };
    return typeClasses[fileType] || 'bg-gray-100 text-gray-800';
  }

  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  showError(message) {
    this.dispatchToast(message || this.translations.genericError, 'error');
  }

  dispatchToast(notificationHtmlOrMessage, type = 'success') {
    let notificationHtml = notificationHtmlOrMessage;
    
    if (!notificationHtmlOrMessage || (typeof notificationHtmlOrMessage === 'string' && !notificationHtmlOrMessage.includes('data-toast-target'))) {
      const bgColor = type === 'success' 
        ? 'bg-[#FFFFFF] border-[#E3E3E3] border-l-4 border-l-[#5C3984]'
        : type === 'info'
        ? 'bg-[#FFFFFF] border-[#E3E3E3] border-l-4 border-l-blue-500'
        : 'bg-[#FFFFFF] border-[#E3E3E3] border-l-4 border-l-red-500';
      
      const icon = type === 'success'
        ? '<svg class="w-5 h-5 text-[#5C3984]" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/></svg>'
        : type === 'info'
        ? '<svg class="w-5 h-5 text-blue-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"/></svg>'
        : '<svg class="w-5 h-5 text-red-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/></svg>';

      notificationHtml = `
        <div 
          data-toast-target="notification"
          class="${bgColor} rounded-lg shadow-lg p-4 flex items-start gap-3 transform opacity-0 translate-x-full transition ease-out duration-300"
        >
          ${icon}
          <div class="flex-1 text-sm text-[#0D1120] font-medium">
            ${notificationHtmlOrMessage}
          </div>
          <button 
            data-action="click->toast#close"
            class="text-gray-400 hover:text-gray-600 transition-colors"
          >
            <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"/>
            </svg>
          </button>
        </div>
      `;
    }

    if (!notificationHtml) return;

    const event = new CustomEvent('toast:show', {
      detail: { notificationHtml },
      bubbles: true
    });
    document.dispatchEvent(event);
  }
}
