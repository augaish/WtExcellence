import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="capa-link-clauses-search"
export default class extends Controller {
  static targets = [];
  
  connect() {
    this.selectedItems = [];
    this.searchTimeout = null;
    this.lastSearchResults = []; // Store search results to get full item data
    this.translations = {
      searchLoading: this.element.dataset.searchLoadingText || 'Searching...',
      searchComingSoon: this.element.dataset.searchComingSoonText || 'Search functionality coming soon...',
      smartSuggestLabel: this.element.dataset.smartSuggestLabelText || 'Smart Suggest',
      smartSuggestLoading: this.element.dataset.smartSuggestLoadingText || 'Suggesting...',
      smartSuggestAnalyzing: this.element.dataset.smartSuggestAnalyzingText || 'Analyzing CAPA and suggesting relevant clauses...',
      smartSuggestError: this.element.dataset.smartSuggestErrorText || 'Failed to suggest clauses',
      noResults: this.element.dataset.noResultsText || 'No results found',
      addLabel: this.element.dataset.addLabelText || 'Add',
      addedLabel: this.element.dataset.addedLabelText || 'Added',
      clauseAdded: this.element.dataset.clauseAddedText || 'Clause added!',
      selectAtLeastOne: this.element.dataset.selectAtLeastOneText || 'Please select at least one clause',
      capaIdMissing: this.element.dataset.capaIdMissingText || 'CAPA ID not found',
      linking: this.element.dataset.linkingText || 'Linking...',
      linkSuccessTemplate: this.element.dataset.linkSuccessTemplate || '%{count} clause(s) linked successfully!',
      linkFailed: this.element.dataset.linkFailedText || 'Failed to link clauses. Please try again.',
      genericError: this.element.dataset.genericErrorText || 'An error occurred. Please try again.',
      searchError: this.element.dataset.searchErrorText || 'Search failed. Please try again.',
      standardFallback: this.element.dataset.standardFallbackText || 'Standard',
      typeClause: this.element.dataset.typeClauseText || 'Clause',
      typeSubClause: this.element.dataset.typeSubClauseText || 'Sub-Clause'
    };
    
    // Get CAPA ID from the page (from data attribute or URL)
    const capaIdElement = document.querySelector('[data-capa-id]');
    this.capaId = capaIdElement?.dataset.capaId || window.location.pathname.match(/\/capa_management\/([^\/]+)/)?.[1];
    
    // Setup submit button handler
    const submitButton = document.getElementById('link_clauses_submit');
    if (submitButton) {
      submitButton.addEventListener('click', () => this.handleSave());
    }
    
    // Setup Smart Suggest button handler
    const smartSuggestButton = document.getElementById('smart_suggest_button');
    if (smartSuggestButton) {
      smartSuggestButton.addEventListener('click', (e) => this.smartSuggest(e));
    }
    
    // Use event delegation for dynamically added buttons
    const resultsDiv = document.getElementById('link_clauses_results');
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
    const resultsDiv = document.getElementById('link_clauses_results');
    
    if (!resultsDiv) return;

    // Show loading state
    resultsDiv.classList.remove('hidden');
    resultsDiv.innerHTML = `<div class="text-center py-4 text-gray-500">${this.translations.searchLoading}</div>`;

    try {
      const response = await fetch(`/api/search/clauses?q=${encodeURIComponent(query)}`, {
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
      resultsDiv.innerHTML = `<div class="text-center py-4 text-gray-500">${this.translations.searchComingSoon}</div>`;
    }
  }

  async smartSuggest(event) {
    const button = event.currentTarget;
    const capaId = button.dataset.capaId || this.capaId;
    
    if (!capaId) {
      console.error('CAPA ID not found');
      return;
    }

    const resultsDiv = document.getElementById('link_clauses_results');
    if (!resultsDiv) return;

    // Get spinner, icon, and text elements
    const spinner = button.querySelector('[data-smart-suggest-spinner]');
    const icon = button.querySelector('[data-smart-suggest-icon]');
    const text = button.querySelector('[data-smart-suggest-text]');

    // Show loading state
    button.disabled = true;
    if (spinner) spinner.classList.remove('hidden');
    if (icon) icon.classList.add('hidden');
    if (text) text.textContent = this.translations.smartSuggestLoading;

    // Show loading in results area
    resultsDiv.classList.remove('hidden');
    resultsDiv.innerHTML = `<div class="text-center py-4 text-gray-500">${this.translations.smartSuggestAnalyzing}</div>`;

    try {
      const response = await fetch(`/dashboard/capa_management/${capaId}/suggest_clauses`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Accept': 'application/json',
          'Content-Type': 'application/json'
        }
      });

      const result = await response.json();

      if (!response.ok) {
        throw new Error(result.error || this.translations.smartSuggestError);
      }

      // Show success notification
      if (result.notification_html) {
        const notificationContainer = document.getElementById('notification-container') || document.body;
        const temp = document.createElement('div');
        temp.innerHTML = result.notification_html.trim();
        const notification = temp.firstElementChild;
        if (notification && notificationContainer) {
          notificationContainer.appendChild(notification);
          // Auto-remove after 5 seconds
          setTimeout(() => {
            if (notification.parentNode) {
              notification.remove();
            }
          }, 5000);
        }
      }

      // Store results for later use when adding items
      this.lastSearchResults = result.results || [];
      this.displayResults(result.results || []);

      // Show summary if available
      if (result.summary) {
        const summaryDiv = document.createElement('div');
        summaryDiv.className = 'mt-2 p-2 bg-blue-50 text-blue-700 text-sm rounded border border-blue-200';
        summaryDiv.textContent = result.summary;
        resultsDiv.insertBefore(summaryDiv, resultsDiv.firstChild);
      }
    } catch (error) {
      console.error('Error suggesting clauses:', error);
      const errorMessage = error.message || this.translations.smartSuggestError;
      resultsDiv.innerHTML = `<div class="text-center py-4 text-red-500">${this.escapeHtml(errorMessage)}</div>`;
    } finally {
      // Reset button state
      button.disabled = false;
      if (spinner) spinner.classList.add('hidden');
      if (icon) icon.classList.remove('hidden');
      if (text) text.textContent = this.translations.smartSuggestLabel;
    }
  }

  displayResults(results) {
    const resultsDiv = document.getElementById('link_clauses_results');
    
    if (!resultsDiv) return;

    if (results.length === 0) {
      resultsDiv.innerHTML = `<div class="text-center py-4 text-gray-500">${this.translations.noResults}</div>`;
      return;
    }

    let html = '<div class="space-y-2">';
    results.forEach(item => {
      // Check if clause is already selected
      const isSelected = this.selectedItems.find(selected => 
        selected.id === item.id
      );
      
      const buttonHtml = isSelected
        ? `
          <button type="button" class="ml-3 px-3 py-1 text-sm bg-green-100 text-green-700 rounded flex items-center gap-1" disabled>
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
            </svg>
            ${this.translations.addedLabel}
          </button>
        `
        : `
          <button type="button" class="ml-3 px-3 py-1 text-sm text-[#5C3984] hover:text-[#4A2F6B] hover:bg-purple-50 rounded" data-add-item="true" data-item-id="${item.id}" data-item-type="${item.type}" data-item-title="${this.escapeHtml(item.title || 'Untitled')}" data-standard-name="${this.escapeHtml(item.standard_name || '')}" data-clause-code="${this.escapeHtml(item.code || '')}" data-is-sub-clause="${item.is_sub_clause ? 'true' : 'false'}">
            ${this.translations.addLabel}
          </button>
        `;
      
      // Display clause code and title
      const clauseDisplay = item.code ? `${item.code} ${item.title || ''}`.trim() : (item.title || 'Untitled');
      
      // Show reasoning if available (from AI suggestions)
      const reasoningHtml = item.reasoning 
        ? `<div class="text-xs text-blue-600 mt-1 italic">${this.escapeHtml(item.reasoning)}</div>`
        : '';
      
      html += `
        <div class="flex items-center justify-between p-3 border border-gray-200 rounded-lg hover:bg-gray-50 ${isSelected ? 'bg-green-50 border-green-200' : ''}" data-item-id="${item.id}" data-item-type="${item.type}">
          <div class="flex-1">
            <div class="font-medium text-[#0D1120]">${this.escapeHtml(clauseDisplay)}</div>
            <div class="text-sm text-gray-500">
              ${this.escapeHtml(item.type)} • ${this.escapeHtml(item.standard_name || 'Standard')}
            </div>
            ${reasoningHtml}
          </div>
          ${buttonHtml}
        </div>
      `;
    });
    html += '</div>';
    
    resultsDiv.innerHTML = html;
  }

  addItemFromButton(button) {
    const itemId = button.dataset.itemId;
    const itemType = button.dataset.itemType;
    const itemTitle = button.dataset.itemTitle;
    
    // Get the full item data from the result row
    const resultItem = button.closest('[data-item-id]');
    const itemData = this.getItemDataFromResult(resultItem);
    
    if (!itemId || !itemType) {
      console.error('Missing item data:', { itemId, itemType });
      return;
    }
    
    // Check if already selected
    if (this.selectedItems.find(item => item.id === itemId)) {
      return;
    }

    // Get data from button or search results
    const standardName = button.dataset.standardName || itemData.standard_name || '';
    const clauseCode = button.dataset.clauseCode || itemData.code || '';
    const isSubClause = button.dataset.isSubClause === 'true' || itemData.is_sub_clause || false;
    
    // Add to selected items with all available data
    this.selectedItems.push({
      id: itemId, // This is the Clause ID
      type: itemType, // 'Clause' or 'Sub-Clause'
      title: itemTitle || itemData.title,
      code: clauseCode,
      standard_name: standardName,
      is_sub_clause: isSubClause
    });

    // Update the button in the results to show "Added"
    this.updateResultButton(itemId, itemType, true);
    
    this.updateSelectedItemsDisplay();
    this.updateSubmitButton();
    
    // Show a brief visual feedback
    this.showFeedback(this.translations.clauseAdded);
  }

  getItemDataFromResult(resultItem) {
    if (!resultItem) return {};
    
    const itemId = resultItem.dataset.itemId;
    
    // Find the item in last search results to get full data
    const searchResult = this.lastSearchResults.find(r => r.id === itemId);
    
    if (searchResult) {
      return {
        title: searchResult.title || '',
        type: searchResult.type || '',
        code: searchResult.code || '',
        standard_name: searchResult.standard_name || '',
        is_sub_clause: searchResult.is_sub_clause || false
      };
    }
    
    // Fallback: extract from DOM
    const titleDiv = resultItem.querySelector('.font-medium');
    const typeDiv = resultItem.querySelector('.text-sm.text-gray-500');
    
    return {
      title: titleDiv?.textContent?.trim() || '',
      type: typeDiv?.textContent?.split('•')[0]?.trim() || '',
      code: '',
      standard_name: typeDiv?.textContent?.split('•')[1]?.trim() || '',
      is_sub_clause: false
    };
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
    // Find by ID
    const resultItem = document.querySelector(`[data-item-id="${itemId}"]`);
    if (!resultItem) return;
    
    const buttonContainer = resultItem.querySelector('.ml-3');
    if (!buttonContainer) return;
    
    // Get item title from the result item
    const itemTitle = resultItem.querySelector('.font-medium')?.textContent || 'Untitled';
    
    if (isAdded) {
      buttonContainer.innerHTML = `
        <button type="button" class="px-3 py-1 text-sm bg-green-100 text-green-700 rounded flex items-center gap-1" disabled>
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
          </svg>
          Added
        </button>
      `;
      resultItem.classList.add('bg-green-50', 'border-green-200');
      resultItem.classList.remove('hover:bg-gray-50');
    } else {
      // Find the item in last search results to get full data
      const searchResult = this.lastSearchResults.find(r => r.id === itemId);
      const standardName = searchResult?.standard_name || this.translations.standardFallback;
      const clauseCode = searchResult?.code || '';
      const isSubClause = searchResult?.is_sub_clause || false;
      
      buttonContainer.innerHTML = `
        <button type="button" class="ml-3 px-3 py-1 text-sm text-[#5C3984] hover:text-[#4A2F6B] hover:bg-purple-50 rounded" data-add-item="true" data-item-id="${itemId}" data-item-type="${itemType}" data-item-title="${this.escapeHtml(itemTitle)}" data-standard-name="${this.escapeHtml(standardName)}" data-clause-code="${this.escapeHtml(clauseCode)}" data-is-sub-clause="${isSubClause ? 'true' : 'false'}">
          Add
        </button>
      `;
      resultItem.classList.remove('bg-green-50', 'border-green-200');
      resultItem.classList.add('hover:bg-gray-50');
    }
  }

  updateSelectedItemsDisplay() {
    const selectedDiv = document.getElementById('link_clauses_selected');
    const selectedList = document.getElementById('selected_clauses_list');
    
    if (!selectedDiv || !selectedList) return;

    if (this.selectedItems.length === 0) {
      selectedDiv.classList.add('hidden');
      return;
    }

    selectedDiv.classList.remove('hidden');
    
    // Create table structure
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
      // Determine type display: Show "Clause" or "Sub-Clause"
    const typeDisplay = item.is_sub_clause ? this.translations.typeSubClause : this.translations.typeClause;
      
      // Format name: Standard name (bold) on first line, clause code + title on second line
      const standardName = item.standard_name || 'Standard';
      const clauseDisplay = item.code && item.title 
        ? `${item.code} ${item.title}`
        : item.code || item.title || '';
      
      const nameHtml = `
        <div>
          <div class="font-semibold text-[#0D1120]">${this.escapeHtml(standardName)}</div>
          <div class="text-sm text-gray-700">${this.escapeHtml(clauseDisplay)}</div>
        </div>
      `;
      
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

  updateSubmitButton() {
    const submitButton = document.getElementById('link_clauses_submit');
    if (submitButton) {
      submitButton.disabled = this.selectedItems.length === 0;
    }
  }

  hideResults() {
    const resultsDiv = document.getElementById('link_clauses_results');
    if (resultsDiv) {
      resultsDiv.classList.add('hidden');
    }
  }

  async handleSave() {
    if (this.selectedItems.length === 0) {
      this.showFeedback(this.translations.selectAtLeastOne, 'error');
      return;
    }

    if (!this.capaId) {
      this.showFeedback(this.translations.capaIdMissing, 'error');
      return;
    }

    const submitButton = document.getElementById('link_clauses_submit');
    const originalText = submitButton.textContent;
    
    // Disable button and show loading
    submitButton.disabled = true;
    submitButton.textContent = this.translations.linking;
    submitButton.classList.add('opacity-50');

    try {
      const response = await fetch(`/dashboard/capa_management/${this.capaId}/link_clauses`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || '',
          'X-Requested-With': 'XMLHttpRequest'
        },
        body: JSON.stringify({
          items: this.selectedItems.map(item => ({
            id: item.id // Clause ID
          }))
        })
      });

      const data = await response.json();

      if (response.ok && data.success) {
        // Show success message
        const successText = data.message || this.translations.linkSuccessTemplate.replace('%{count}', this.selectedItems.length);
        this.showFeedback(successText, 'success');
        
        // Close modal after a brief delay
        setTimeout(() => {
          // Close the modal
          const modal = document.getElementById('link_clauses_dialog');
          if (modal) {
            modal.close();
          }
          
          // Reload the page to show updated linked clauses
          window.location.reload();
        }, 1000);
      } else {
        // Show error message
        const errorMsg = data.message || data.error || this.translations.linkFailed;
        this.showFeedback(errorMsg, 'error');
        
        // Re-enable button
        submitButton.disabled = false;
        submitButton.textContent = originalText;
        submitButton.classList.remove('opacity-50');
      }
    } catch (error) {
      console.error('Link clauses error:', error);
      this.showFeedback(this.translations.genericError, 'error');
      
      // Re-enable button
      submitButton.disabled = false;
      submitButton.textContent = originalText;
      submitButton.classList.remove('opacity-50');
    }
  }

  showFeedback(message, type = 'success') {
    // Remove existing feedback if any
    const existingFeedback = document.getElementById('link_clauses_feedback');
    if (existingFeedback) {
      existingFeedback.remove();
    }

    // Create feedback element
    const feedback = document.createElement('div');
    feedback.id = 'link_clauses_feedback';
    feedback.className = `mt-4 p-3 rounded-lg text-sm ${
      type === 'success' 
        ? 'bg-green-50 text-green-700 border border-green-200' 
        : 'bg-red-50 text-red-700 border border-red-200'
    }`;
    feedback.textContent = message;

    // Insert feedback before the selected items section
    const selectedDiv = document.getElementById('link_clauses_selected');
    if (selectedDiv && selectedDiv.parentNode) {
      selectedDiv.parentNode.insertBefore(feedback, selectedDiv);
    } else {
      // Fallback: insert before footer
      const footer = document.querySelector('#link_clauses_dialog .border-t');
      if (footer && footer.parentNode) {
        footer.parentNode.insertBefore(feedback, footer);
      }
    }

    // Auto-remove after 5 seconds (unless it's a success message that will reload)
    if (type !== 'success') {
      setTimeout(() => {
        if (feedback.parentNode) {
          feedback.remove();
        }
      }, 5000);
    }
  }
}

