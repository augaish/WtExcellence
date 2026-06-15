import { Controller } from "@hotwired/stimulus";
import Choices from "choices.js";

export default class extends Controller {
  static targets = ["clauseContainer", "selectedClausesContainer", "selectedClausesList", "submitButton"];
  static values = { standard: String };

  clausesData = null; // Store clauses data for terminal count lookup
  selectedClauses = []; // Track selected clauses

  connect() {
    this.clauseChoices = null;

    // Initialize top-level clause select if it exists
    const clauseSelect = this.element.querySelector('#tool_top_level_clause_id');
    if (clauseSelect) {
      this.initChoices(clauseSelect);
    }

    // If there's already a standard selected, load clauses
    if (this.standardValue) {
      setTimeout(() => {
        this.loadClauses(this.standardValue);
      }, 100);
    }
  }

  disconnect() {
    this.destroyChoices();
  }

  initChoices(element) {
    if (this.clauseChoices) return;

    this.clauseChoices = new Choices(element, {
      allowHTML: false,
      searchEnabled: true,
      shouldSort: false,
      itemSelectText: "",
      placeholder: true,
      placeholderValue: "Select a top-level clause",
      noResultsText: "No results found",
      noChoicesText: "No options available",
    });
  }

  destroyChoices() {
    if (this.clauseChoices) {
      this.clauseChoices.destroy();
      this.clauseChoices = null;
    }
  }

  handleStandardChange(standardId) {
    if (standardId) {
      this.loadClauses(standardId);
      // Reset selected clauses when standard changes
      this.selectedClauses = [];
      this.renderSelectedClauses();
    } else {
      if (this.hasClauseContainerTarget) {
        this.clauseContainerTarget.classList.add('hidden');
      }
      if (this.hasSelectedClausesContainerTarget) {
        this.selectedClausesContainerTarget.classList.add('hidden');
      }
      this.clearClauses();
      this.selectedClauses = [];
    }
  }

  loadClauses(eventOrStandardId) {
    // Handle both event object and direct standardId parameter
    let standardId;
    if (eventOrStandardId && typeof eventOrStandardId === 'object' && eventOrStandardId.target) {
      standardId = eventOrStandardId.target.value;
    } else {
      standardId = eventOrStandardId;
    }

    if (!standardId) {
      if (this.hasClauseContainerTarget) {
        this.clauseContainerTarget.classList.add('hidden');
      }
      this.clearClauses();
      return;
    }

    // Show the clause container
    if (this.hasClauseContainerTarget) {
      this.clauseContainerTarget.classList.remove('hidden');
    }

    const clauseSelect = this.element.querySelector('#tool_top_level_clause_id');
    if (!clauseSelect) return;

    // Get current tool ID from the form action URL
    const form = clauseSelect.closest('form');
    let toolId = null;
    if (form && form.action) {
      const match = form.action.match(/\/tools\/([^\/]+)\/link_standard/);
      if (match) {
        toolId = match[1];
      }
    }

    // Build API URL
    const apiUrl = toolId
      ? `/api/standards/${standardId}/terminal_clauses?tool_id=${toolId}`
      : `/api/standards/${standardId}/terminal_clauses`;

    // Fetch top-level clauses from API
    fetch(apiUrl, {
      headers: {
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest'
      }
    })
      .then(response => response.json())
      .then(data => {
        // Store clauses data for later use
        this.clausesData = data.clauses || [];

        // Prep choices for Choices.js — skip clauses already assigned to another tool
        const choices = this.clausesData
          .filter(clause => !clause.already_assigned)
          .map(clause => ({
            value: String(clause.id),
            label: `${clause.code} - ${clause.title} (${clause.terminal_count} terminal clauses)`,
            customProperties: {
              terminalCount: clause.terminal_count || 0,
              basePoints: clause.base_points || 0,
              code: clause.code,
              title: clause.title
            }
          }));

        if (this.clauseChoices) {
          this.clauseChoices.setChoices(choices, 'value', 'label', true);
        }
      })
      .catch(error => {
        console.error('Error loading clauses:', error);
      });
  }

  addClause(event) {
    event.preventDefault();

    if (!this.clauseChoices) return;

    const val = this.clauseChoices.getValue(true);
    if (!val) {
      alert('Please select a clause first');
      return;
    }

    const fullChoice = this.clauseChoices.getValue();
    const props = fullChoice.customProperties || {};

    const clauseId = fullChoice.value;
    const clauseCode = props.code || fullChoice.label.split(' - ')[0];
    const clauseTitle = props.title || fullChoice.label.split(' - ')[1]?.split(' (')[0] || '';
    const terminalCount = props.terminalCount || 0;

    // Check if already added
    if (this.selectedClauses.find(c => c.id === String(clauseId))) {
      alert('This clause has already been added');
      return;
    }

    // Add to selected clauses
    const newClause = {
      id: String(clauseId),
      code: clauseCode,
      title: clauseTitle,
      terminalCount: terminalCount
    };

    this.selectedClauses.push(newClause);

    // Reset select
    this.clauseChoices.removeActiveItems();

    // Render the list
    this.renderSelectedClauses();
  }

  removeClause(event) {
    event.preventDefault();
    const clauseId = event.currentTarget.dataset.clauseId;
    this.selectedClauses = this.selectedClauses.filter(c => c.id !== String(clauseId));
    this.renderSelectedClauses();
  }

  renderSelectedClauses() {
    if (!this.hasSelectedClausesListTarget) return;

    if (this.selectedClauses.length === 0) {
      if (this.hasSelectedClausesContainerTarget) {
        this.selectedClausesContainerTarget.classList.add('hidden');
      }
      return;
    }

    // Show container
    if (this.hasSelectedClausesContainerTarget) {
      this.selectedClausesContainerTarget.classList.remove('hidden');
    }

    // Render list
    this.selectedClausesListTarget.innerHTML = this.selectedClauses.map(clause => `
      <div class="flex items-center gap-4 p-4 bg-white rounded-lg border border-[#E3E3E3] hover:border-[#5C3984] transition-colors">
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2 mb-1">
            <span class="text-sm font-semibold text-[#0D1120]">${clause.code}</span>
            <span class="text-sm text-[#797C81] truncate">${clause.title}</span>
          </div>
          <div class="flex items-center gap-2">
            <svg class="w-4 h-4 text-[#5C3984]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
            </svg>
            <span class="text-xs text-[#5C3984] font-medium">${clause.terminalCount} terminal clause(s)</span>
          </div>
        </div>
        <div class="flex items-center gap-3 flex-shrink-0">
          <button
            type="button"
            data-clause-id="${clause.id}"
            data-action="click->tool-clause-loader#removeClause"
            class="text-red-600 hover:text-red-800 hover:bg-red-50 p-2 rounded transition-colors"
            title="Remove clause">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
            </svg>
          </button>
        </div>
      </div>
    `).join('');
  }

  handleFormSubmit(event) {
    if (this.selectedClauses.length === 0) {
      event.preventDefault();
      alert('Please add at least one clause');
      return;
    }

    // Add hidden fields for each clause with its points
    const form = event.target;

    // Remove any existing hidden clause fields
    form.querySelectorAll('input[name^="clauses"]').forEach(input => input.remove());

    // Add new hidden fields
    this.selectedClauses.forEach((clause, index) => {
      const clauseIdInput = document.createElement('input');
      clauseIdInput.type = 'hidden';
      clauseIdInput.name = `clauses[${index}][clause_id]`;
      clauseIdInput.value = clause.id;
      form.appendChild(clauseIdInput);
    });
  }

  clearClauses() {
    if (this.clauseChoices) {
      this.clauseChoices.clearChoices();
      this.clauseChoices.setChoices([{ value: '', label: 'Select a top-level clause', placeholder: true }], 'value', 'label', true);
    }
    this.clausesData = null;
  }
}

