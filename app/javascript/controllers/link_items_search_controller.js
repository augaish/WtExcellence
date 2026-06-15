import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="link-items-search"
export default class extends Controller {
  static targets = [];
  
  connect() {
    this.selectedItems = [];
    this.searchTimeout = null;
    this.lastSearchResults = []; // Store search results to get full item data
    
    // Get upload ID from the page (from data attribute or URL)
    const uploadIdElement = document.querySelector('[data-upload-id]');
    this.uploadId = uploadIdElement?.dataset.uploadId || window.location.pathname.match(/\/uploads\/([^\/]+)/)?.[1];
    
    // Setup submit button handler
    const submitButton = document.getElementById('link_items_submit');
    if (submitButton) {
      submitButton.addEventListener('click', () => this.handleSave());
    }
    
    // Use event delegation for dynamically added buttons
    const resultsDiv = document.getElementById('link_items_results');
    if (resultsDiv) {
      resultsDiv.addEventListener('click', (e) => {
        const button = e.target.closest('[data-add-item]');
        if (button) {
          e.preventDefault();
          e.stopPropagation();
          this.addItemFromButton(button);
        }
      });
    }
  }

  handleSearch(event) {
    const query = event.target.value.trim();
    
    // Clear previous timeout
    if (this.searchTimeout) {
      clearTimeout(this.searchTimeout);
    }

    // If query is empty, hide results
    if (query.length === 0) {
      this.hideResults();
      return;
    }

    // Debounce search
    this.searchTimeout = setTimeout(() => {
      this.performSearch(query);
    }, 300);
  }

  async performSearch(query) {
    const resultsDiv = document.getElementById('link_items_results');
    const submitButton = document.getElementById('link_items_submit');
    
    if (!resultsDiv) return;

    // Show loading state
    resultsDiv.classList.remove('hidden');
    resultsDiv.innerHTML = '<div class="text-center py-4 text-gray-500">Searching...</div>';

    try {
      const response = await fetch(`/api/search?q=${encodeURIComponent(query)}`, {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      });

      if (response.ok) {
        const data = await response.json();
      
        // Store results for later use when adding items
        this.lastSearchResults = data.results || [];
        this.displayResults(data.results || []);
      } else {
        console.error('Search request failed:', response.status, response.statusText);
        // Fallback: show empty state
        this.displayResults([]);
      }
    } catch (error) {
      console.error('Search error:', error);
      // Show empty state on error
      resultsDiv.innerHTML = '<div class="text-center py-4 text-gray-500">Search functionality coming soon...</div>';
    }
  }

  displayResults(results) {
    const resultsDiv = document.getElementById('link_items_results');
    
    if (!resultsDiv) return;

    if (results.length === 0) {
      resultsDiv.innerHTML = '<div class="text-center py-4 text-gray-500">No results found</div>';
      return;
    }

    let html = '<div class="space-y-2">';
    results.forEach(item => {
      // Check if item is already selected (check by ID and type)
      const isSelected = this.selectedItems.find(selected => 
        selected.id === item.id && selected.type === item.type
      );
      
      // Generate button HTML based on item type
      let buttonHtml;
      if (isSelected) {
        buttonHtml = `
          <button type="button" class="ml-3 px-3 py-1 text-sm bg-[#F6EEFF] text-[#5C3984] rounded flex items-center gap-1" disabled>
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
            </svg>
            Added
          </button>
        `;
      } else if (item.type === 'Capa') {
        buttonHtml = `
          <button type="button" class="ml-3 px-3 py-1 text-sm text-[#5C3984] hover:text-[#4A2F6B] hover:bg-purple-50 rounded" data-add-item="true" data-item-id="${item.id}" data-item-type="Capa" data-item-name="${this.escapeHtml(item.name || 'Untitled')}">
            Add
          </button>
        `;
      } else {
        buttonHtml = `
          <button type="button" class="ml-3 px-3 py-1 text-sm text-[#5C3984] hover:text-[#4A2F6B] hover:bg-purple-50 rounded" data-add-item="true" data-item-id="${item.id}" data-item-type="Checkpoint" data-item-name="${this.escapeHtml(item.name || item.title || 'Untitled')}" data-standard-name="${this.escapeHtml(item.standard_name || '')}" data-clause-code="${this.escapeHtml(item.clause_code || '')}" data-clause-name="${this.escapeHtml(item.clause_name || '')}" data-clause-id="${item.clause_id || ''}" data-is-sub-clause="${item.is_sub_clause ? 'true' : 'false'}">
            Add
          </button>
        `;
      }
      
      // Display checkpoint name with clause context
      const checkpointName = item.name || 'Untitled';
      const clauseContext = item.clause_code ? `${item.clause_code} ${item.clause_name || ''}`.trim() : '';
      
      if (item.type === 'Capa') {
        html += `
          <div class="flex items-center justify-between p-3 border rounded-lg ${isSelected ? 'bg-[#F6EEFF] border-[#5C3984] border-2' : 'border-gray-200 hover:bg-purple-50'}" data-item-id="${item.id}" data-item-type="${item.type}">
            <div class="flex-1">
              <div class="font-medium text-[#0D1120]">${this.escapeHtml(item.name || 'Untitled')}</div>
              <div class="text-sm text-gray-500">
                ${this.escapeHtml('Capa')}
              </div>
            </div>
            ${buttonHtml}
          </div>
        `;
      } else {
      html += `
        <div class="flex items-center justify-between p-3 border rounded-lg ${isSelected ? 'bg-[#F6EEFF] border-[#5C3984] border-2' : 'border-gray-200 hover:bg-purple-50'}" data-item-id="${item.id}" data-item-type="${item.type}">
          <div class="flex-1">
            <div class="font-medium text-[#0D1120]">${this.escapeHtml(item.type)}</div>
            <div class="font-medium text-[#0D1120]">${this.escapeHtml(checkpointName)}</div>
            <div class="text-sm text-gray-500">
              ${clauseContext ? `${this.escapeHtml(clauseContext)} • ` : ''}${this.escapeHtml(item.type)} • ${this.escapeHtml(item.code || '')}
            </div>
          </div>
          ${buttonHtml}
        </div>
      `;
    }
    });
    html += '</div>';
    
    resultsDiv.innerHTML = html;
  }

  addItemFromButton(button) {
    const itemId = button.dataset.itemId;
    const itemType = button.dataset.itemType;
    const itemName = button.dataset.itemName;
    
    // Get the full item data from the result row
    const resultItem = button.closest('[data-item-id]');
    const itemData = this.getItemDataFromResult(resultItem);
    
    if (!itemId || !itemType) {
      console.error('Missing item data:', { itemId, itemType });
      return;
    }
    
    // Check if already selected (check by ID and type)
    if (this.selectedItems.find(item => item.id === itemId && item.type === itemType)) {
      return;
    }

    // Handle Capas differently from Checkpoints
    if (itemType === 'Capa') {
      // For Capas, get description from search results
      const searchResult = this.lastSearchResults.find(r => r.id === itemId && r.type === 'Capa');
      this.selectedItems.push({
        id: itemId,
        type: 'Capa',
        name: itemName || itemData.name || searchResult?.name || 'Untitled Capa',
        description: searchResult?.description || itemData.description || ''
      });
    } else {
      // For Checkpoints, get standard and clause data
      const standardName = button.dataset.standardName || itemData.standard_name || '';
      const clauseCode = button.dataset.clauseCode || itemData.clause_code || '';
      const clauseName = button.dataset.clauseName || itemData.clause_name || '';
      const clauseId = button.dataset.clauseId || itemData.clause_id || '';
      const isSubClause = button.dataset.isSubClause === 'true' || itemData.is_sub_clause || false;
      
      this.selectedItems.push({
        id: itemId,
        type: 'Checkpoint',
        name: itemName || itemData.name,
        standard_name: standardName,
        code: itemData.code || '',
        clause_code: clauseCode,
        clause_name: clauseName,
        clause_id: clauseId,
        is_sub_clause: isSubClause
      });
    }

    // Update the button in the results to show "Added"
    this.updateResultButton(itemId, itemType, true);
    
    this.updateSelectedItemsDisplay();
    this.updateSubmitButton();
    
    // Show a brief visual feedback
    this.showFeedback('Item added!');
  }

  getItemDataFromResult(resultItem) {
    if (!resultItem) return {};
    
    const itemId = resultItem.dataset.itemId;
    const itemType = resultItem.dataset.itemType;
    
    // Find the item in last search results to get full data
    const searchResult = this.lastSearchResults.find(r => r.id === itemId && r.type === itemType);
    
    if (searchResult) {
      if (searchResult.type === 'Capa') {
        return {
          name: searchResult.name || '',
          type: searchResult.type || '',
          description: searchResult.description || ''
        };
      } else {
        return {
          name: searchResult.name || '',
          type: searchResult.type || '',
          code: searchResult.code || '',
          standard_name: searchResult.standard_name || '',
          full_code: searchResult.full_code || searchResult.code || ''
        };
      }
    }
    
    // Fallback: extract from DOM
    const nameDiv = resultItem.querySelector('.font-medium');
    const typeDiv = resultItem.querySelector('.text-sm.text-gray-500');
    
    if (itemType === 'Capa') {
      return {
        name: nameDiv?.textContent?.trim() || '',
        type: 'Capa',
        description: ''
      };
    } else {
      return {
        name: nameDiv?.textContent?.trim() || '',
        type: typeDiv?.textContent?.split('•')[0]?.trim() || '',
        code: typeDiv?.textContent?.split('•')[1]?.trim() || '',
        standard_name: null,
        full_code: null
      };
    }
  }

  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }


  removeSelectedItem(itemId, itemType) {
    this.selectedItems = this.selectedItems.filter(
      item => !(item.id === itemId && item.type === itemType)
    );
    
    // Update the button in the results back to "Add"
    this.updateResultButton(itemId, itemType, false);
    
    this.updateSelectedItemsDisplay();
    this.updateSubmitButton();
  }

  updateResultButton(itemId, itemType, isAdded) {
    // Find by ID only since all items are checkpoints
    const resultItem = document.querySelector(`[data-item-id="${itemId}"]`);
    if (!resultItem) return;
    
    const buttonContainer = resultItem.querySelector('.ml-3');
    if (!buttonContainer) return;
    
    // Get item name from the result item
    const itemName = resultItem.querySelector('.font-medium')?.textContent || 'Untitled';
    
    if (isAdded) {
      buttonContainer.innerHTML = `
        <button type="button" class="px-3 py-1 text-sm bg-[#F6EEFF] text-[#5C3984] rounded flex items-center gap-1" disabled>
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
          </svg>
          Added
        </button>
      `;
      resultItem.classList.add('bg-[#F6EEFF]', 'border-[#5C3984]', 'border-2');
      resultItem.classList.remove('hover:bg-gray-50', 'hover:bg-purple-50', 'border-gray-200');
    } else {
      // Find the item in last search results to get full data
      const searchResult = this.lastSearchResults.find(r => r.id === itemId);
      
      // Handle Capas differently from Checkpoints
      if (itemType === 'Capa') {
        buttonContainer.innerHTML = `
          <button type="button" class="ml-3 px-3 py-1 text-sm text-[#5C3984] hover:text-[#4A2F6B] hover:bg-purple-50 rounded" data-add-item="true" data-item-id="${itemId}" data-item-type="Capa" data-item-name="${this.escapeHtml(itemName)}">
            Add
          </button>
        `;
      } else {
        const standardName = searchResult?.standard_name || '';
        const clauseCode = searchResult?.clause_code || '';
        const clauseName = searchResult?.clause_name || '';
        const clauseId = searchResult?.clause_id || '';
        const isSubClause = searchResult?.is_sub_clause || false;
        
        buttonContainer.innerHTML = `
          <button type="button" class="ml-3 px-3 py-1 text-sm text-[#5C3984] hover:text-[#4A2F6B] hover:bg-purple-50 rounded" data-add-item="true" data-item-id="${itemId}" data-item-type="Checkpoint" data-item-name="${this.escapeHtml(itemName)}" data-standard-name="${this.escapeHtml(standardName)}" data-clause-code="${this.escapeHtml(clauseCode)}" data-clause-name="${this.escapeHtml(clauseName)}" data-clause-id="${clauseId}" data-is-sub-clause="${isSubClause ? 'true' : 'false'}">
            Add
          </button>
        `;
      }
      
      resultItem.classList.remove('bg-[#F6EEFF]', 'border-[#5C3984]', 'border-2');
      resultItem.classList.add('hover:bg-purple-50', 'border-gray-200');
    }
  }

  updateSelectedItemsDisplay() {
    const selectedDiv = document.getElementById('link_items_selected');
    const selectedList = document.getElementById('selected_items_list');
    
    if (!selectedDiv || !selectedList) return;

    if (this.selectedItems.length === 0) {
      selectedDiv.classList.add('hidden');
      return;
    }

    selectedDiv.classList.remove('hidden');
    
    // Create table structure matching the image
    let html = `
      <div class="bg-white rounded-lg border border-gray-200 overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Type</th>
              <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Name</th>
              <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider"></th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
    `;
    
    this.selectedItems.forEach(item => {
      let typeDisplay;
      let nameHtml;
      
      if (item.type === 'Capa') {
        // Display Capa: Show "Capa" as type, name and description
        typeDisplay = 'Capa';
        nameHtml = `
          <div>
            <div class="font-semibold text-[#0D1120]">${this.escapeHtml(item.name || 'Untitled Capa')}</div>
            ${item.description ? `<div class="text-sm text-gray-700">${this.escapeHtml(item.description)}</div>` : ''}
          </div>
        `;
      } else {
        // Display Checkpoint: Show "Clause" or "Sub-Clause" based on the checkpoint's clause
        typeDisplay = item.is_sub_clause ? 'Sub-Clause' : 'Clause';
        
        // Format name: Standard name (bold) on first line, clause code + clause name on second line
        const standardName = item.standard_name || 'Standard';
        const clauseName = item.clause_code && item.clause_name 
          ? `${item.clause_code} ${item.clause_name}`
          : item.clause_code || item.clause_name || '';
        
        nameHtml = `
          <div>
            <div class="font-semibold text-[#0D1120]">${this.escapeHtml(standardName)}</div>
            <div class="text-sm text-gray-700">${this.escapeHtml(clauseName)}</div>
          </div>
        `;
      }
      
      html += `
        <tr class="hover:bg-gray-50">
          <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-700">${this.escapeHtml(typeDisplay)}</td>
          <td class="px-4 py-3 text-sm text-gray-700">${nameHtml}</td>
          <td class="px-4 py-3 whitespace-nowrap text-right">
            <button type="button" class="inline-flex items-center justify-center w-8 h-8 rounded bg-[#F6EEFF] text-blue-600 hover:bg-[#E8D9F5] hover:text-blue-700 transition-colors" data-remove-item="true" data-item-id="${item.id}" data-item-type="${item.type}" title="Remove">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
              </svg>
            </button>
          </td>
        </tr>
      `;
    });
    
    html += `
          </tbody>
        </table>
      </div>
    `;
    
    selectedList.innerHTML = html;
    
    // Attach remove handlers to the new delete buttons
    selectedList.querySelectorAll('[data-remove-item]').forEach(button => {
      button.addEventListener('click', (e) => {
        const itemId = e.currentTarget.dataset.itemId;
        const itemType = e.currentTarget.dataset.itemType;
        this.removeSelectedItem(itemId, itemType);
      });
    });
  }

  handleRemoveItem(event) {
    const itemId = event.currentTarget.dataset.itemId;
    const itemType = event.currentTarget.dataset.itemType;
    this.removeSelectedItem(itemId, itemType);
  }

  updateSubmitButton() {
    const submitButton = document.getElementById('link_items_submit');
    if (submitButton) {
      submitButton.disabled = this.selectedItems.length === 0;
    }
  }

  hideResults() {
    const resultsDiv = document.getElementById('link_items_results');
    if (resultsDiv) {
      resultsDiv.classList.add('hidden');
    }
  }

  async handleSave() {
    if (this.selectedItems.length === 0) {
      this.showFeedback('Please select at least one item', 'error');
      return;
    }

    if (!this.uploadId) {
      this.showFeedback('Upload ID not found', 'error');
      return;
    }

    const submitButton = document.getElementById('link_items_submit');
    const originalText = submitButton.textContent;
    
    // Disable button and show loading
    submitButton.disabled = true;
    submitButton.textContent = 'Linking...';
    submitButton.classList.add('opacity-50');

    try {
      const response = await fetch('/evidence_attachments', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || '',
          'X-Requested-With': 'XMLHttpRequest'
        },
        body: JSON.stringify({
          upload_id: this.uploadId,
          items: this.selectedItems.map(item => ({
            id: item.id,
            type: item.type === 'Capa' ? 'Capa' : 'ChecklistItem' // Send correct type based on item
          }))
        })
      });

      const data = await response.json();

      if (response.ok && data.success) {
        // Show success message
        this.showFeedback(data.message || `${this.selectedItems.length} item(s) linked successfully!`, 'success');
        
        // Close modal after a brief delay
        setTimeout(() => {
          // Close the modal
          const modal = document.getElementById('link_items_dialog');
          if (modal) {
            modal.close();
          }
          
          // Reload the page to show updated linked items
          window.location.reload();
        }, 1000);
      } else {
        // Show error message
        const errorMsg = data.message || data.error || 'Failed to link items. Please try again.';
        this.showFeedback(errorMsg, 'error');
        
        // Re-enable button
        submitButton.disabled = false;
        submitButton.textContent = originalText;
        submitButton.classList.remove('opacity-50');
      }
    } catch (error) {
      console.error('Link items error:', error);
      this.showFeedback('An error occurred. Please try again.', 'error');
      
      // Re-enable button
      submitButton.disabled = false;
      submitButton.textContent = originalText;
      submitButton.classList.remove('opacity-50');
    }
  }

  showFeedback(message, type = 'success') {
    // Remove existing feedback if any
    const existingFeedback = document.getElementById('link_items_feedback');
    if (existingFeedback) {
      existingFeedback.remove();
    }

    // Create feedback element
    const feedback = document.createElement('div');
    feedback.id = 'link_items_feedback';
    feedback.className = `mt-4 p-3 rounded-lg text-sm transition-opacity duration-300 ease-in-out ${
      type === 'success' 
        ? 'bg-[#D6C4ED] text-black rounded-lg' 
        : 'bg-red-50 text-red-700 border border-red-200'
    }`;
    feedback.textContent = message;

    // Insert feedback before the selected items section
    const selectedDiv = document.getElementById('link_items_selected');
    if (selectedDiv && selectedDiv.parentNode) {
      selectedDiv.parentNode.insertBefore(feedback, selectedDiv);
    } else {
      // Fallback: insert before footer
      const footer = document.querySelector('#link_items_dialog .border-t');
      if (footer && footer.parentNode) {
        footer.parentNode.insertBefore(feedback, footer);
      }
    }

    // Auto-remove after 5 seconds with fade-out transition
    setTimeout(() => {
      if (feedback.parentNode) {
        // Fade out by setting opacity to 0 (transition class already applied)
        feedback.style.opacity = '0';
        
        // Remove element after transition completes (300ms matches duration-300)
        setTimeout(() => {
          if (feedback.parentNode) {
            feedback.remove();
          }
        }, 300);
      }
    }, 5000);
  }
}

