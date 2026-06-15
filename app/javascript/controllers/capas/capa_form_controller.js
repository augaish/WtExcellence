import { Controller } from "@hotwired/stimulus";
import Choices from "choices.js";

// Connects to data-controller="capas--capa-form"
export default class extends Controller {
  static targets = ["assignedUsers", "userSelect"];
  static values = { deleteIconPath: String };

  connect() {
    this.choices = null;
    // Choices init deferred to open
    this.choices = null;

    // Listen for modal open to reset form state
    const modal = document.getElementById('newActionModal');
    if (modal) {
      this.modalObserver = new MutationObserver((mutations) => {
        mutations.forEach((mutation) => {
          if (mutation.type === 'attributes' && mutation.attributeName === 'open') {
            if (modal.hasAttribute('open')) {
              this.initChoices();
              this.resetFormState();
            }
          }
        });
      });

      this.modalObserver.observe(modal, {
        attributes: true,
        attributeFilter: ['open']
      });
    }
  }

  disconnect() {
    if (this.choices) {
      this.choices.destroy();
      this.choices = null;
    }

    // Disconnect modal observer
    if (this.modalObserver) {
      this.modalObserver.disconnect();
    }
  }

  initChoices() {
    if (this.choices || !this.userSelectTarget) return;

    try {
      this.choices = new Choices(this.userSelectTarget, {
        allowHTML: true,
        searchEnabled: true,
        placeholder: true,
        placeholderValue: "Select User",
        itemSelectText: '',
        shouldSort: false,
        callbackOnCreateTemplates: (template) => {
          return {
            item: (classNames, data) => {
              return template(`<div style="display: none;" data-item data-id="${data.id}" data-value="${data.value}"></div>`);
            },
            choice: (classNames, data) => {
              const props = data.customProperties || {};
              // Parse dataset properties if customProperties are empty (fallback)
              if (Object.keys(props).length === 0 && data.element) {
                Object.assign(props, data.element.dataset);
              }

              const avatarHtml = props.profileImageUrl
                ? `<img src="${props.profileImageUrl}" class="w-6 h-6 rounded-full object-cover flex-shrink-0" alt="${props.name}">`
                : `<div class="w-6 h-6 rounded-full bg-[#E3E3E3] flex items-center justify-center text-[10px] text-[#0D1120] font-bold flex-shrink-0">${props.name ? props.name.charAt(0).toUpperCase() : '?'}</div>`;

              return template(`
                <div class="choices__item choices__item--choice ${data.disabled ? 'choices__item--disabled' : 'choices__item--selectable'} ${data.groupId > 0 ? 'choices__item--child' : ''
                }" data-select-text="" data-choice ${data.disabled
                  ? 'data-choice-disabled aria-disabled="true"'
                  : 'data-choice-selectable'
                } data-id="${data.id}" data-value="${data.value}" ${data.groupId > 0 ? 'role="treeitem"' : 'role="option"'
                }>
                  <div class="flex items-center gap-3">
                     ${avatarHtml}
                     <div class="flex flex-col">
                       <span class="text-sm font-medium text-[#0D1120]">${data.label}</span>
                       <span class="text-xs text-[#797C81]">${props.role || ''}</span>
                     </div>
                  </div>
                </div>
              `);
            },
          };
        },
      });
    } catch (error) {
      console.error('Error initializing Choices.js:', error);
    }

    // Listen for changes to update external chip list
    this.userSelectTarget.addEventListener('change', () => this.updateChipList());
    this.userSelectTarget.addEventListener('addItem', () => this.updateChipList());
    this.userSelectTarget.addEventListener('removeItem', () => this.updateChipList());
  }

  updateChipList() {
    if (!this.hasAssignedUsersTarget) return;

    const selectedItems = this.choices.getValue();
    this.assignedUsersTarget.innerHTML = '';

    if (selectedItems.length === 0) return;

    selectedItems.forEach(item => {
      const props = item.customProperties || {};
      // Fallback to element dataset if customProperties empty
      if (Object.keys(props).length === 0 && item.element) {
        Object.assign(props, item.element.dataset);
      }

      const name = props.name || item.label;
      const role = props.role || '';
      const avatarUrl = props.profileImageUrl;
      const initial = name ? name.charAt(0).toUpperCase() : '?';

      const chip = document.createElement('div');
      chip.className = 'flex items-center gap-3 h-12 px-3 border border-[#E3E3E3] rounded-xl user-chip bg-[#F7F7FD]';

      const avatarHtml = avatarUrl
        ? `<img src="${avatarUrl}" class="w-7 h-7 rounded-full object-cover flex-shrink-0">`
        : `<div class="w-7 h-7 rounded-full bg-[#D6C4ED] flex items-center justify-center text-xs font-semibold text-[#5C3984] flex-shrink-0">${initial}</div>`;

      const deleteIconPath = this.deleteIconPathValue || (window.assetPaths && window.assetPaths.deleteIcon) || "";

      chip.innerHTML = `
        <div class="flex items-center gap-2 min-w-0 flex-1">
          ${avatarHtml}
          <span class="text-sm text-[#0D1120] truncate font-medium">${this.escapeHtml(name)}</span>
          <span class="text-xs text-[#797C81] flex-shrink-0 bg-white px-2 py-0.5 rounded-full border border-[#E3E3E3]">${this.escapeHtml(role)}</span>
        </div>
        <button type="button" class="text-[#797C81] hover:text-[#EA4034] transition-colors flex-shrink-0 p-1" data-action="click->capas--capa-form#removeUser" data-value="${item.value}">
           <img src="${deleteIconPath}" class="w-4 h-4" alt="Remove name" />
        </button>
      `;
      this.assignedUsersTarget.appendChild(chip);
    });
  }

  removeUser(event) {
    // This now handles clicking the 'x' on the chip
    const button = event.currentTarget;
    const value = button.dataset.value;
    if (value) {
      this.choices.removeActiveItemsByValue(value);
    }
  }

  resetFormState() {
    if (this.choices) {
      this.choices.removeActiveItems();
    }
    if (this.assignedUsersTarget) {
      this.assignedUsersTarget.innerHTML = "";
    }
  }

  // Helper retained for compatibility
  createUserChip(userId, userName, userRole, profileImageUrl) {
    // No longer used directly, kept if needed for reference or deleted
    return document.createElement('div');
  }

  async submitForm(event) {
    event.preventDefault();

    const form = event.target;
    const formData = new FormData(form);

    // Find the submit button, whether it's inside the form or connected via 'form' attribute
    let submitButton = event.submitter;
    if (!submitButton && form.id) {
      submitButton = document.querySelector(`button[type="submit"][form="${form.id}"]`);
    }
    if (!submitButton) {
      submitButton = form.querySelector('button[type="submit"]');
    }

    const originalContent = submitButton ? submitButton.innerHTML : "";

    try {
      // Show loading state
      if (submitButton) {
        const span = submitButton.querySelector('span');
        if (span) {
          span.textContent = "Creating...";
        } else {
          submitButton.textContent = "Creating...";
        }
        submitButton.disabled = true;
      }

      const response = await fetch("/dashboard/capa_management", {
        method: "POST",
        body: formData,
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
        },
      });

      if (response.ok) {
        const result = await response.json();

        // Show toast notification
        if (result.notification_html) {
          this.dispatchToast(result.notification_html);
        } else {
          this.showSuccess(result.message || "CAPA created successfully!");
        }

        // Reset form
        form.reset();
        // Use resetFormState() for consistency
        this.resetFormState();

        // Close the modal
        const modal = document.getElementById('newActionModal');
        if (modal) modal.close();

        // Update UI dynamically instead of reloading
        this.updateUIAfterCreate(result);
      } else {
        const error = await response.json();
        if (error.notification_html) {
          this.dispatchToast(error.notification_html);
        } else {
          this.showError(error.message || "CAPA creation failed. Please try again.");
        }
      }
    } catch (error) {
      console.error("CAPA creation error:", error);
      this.showError(error);
    } finally {
      // Reset button state
      if (submitButton) {
        submitButton.innerHTML = originalContent;
        submitButton.disabled = false;
      }
    }
  }

  showSuccess(message) {
    if (!message) return;
    this.dispatchToast(message, 'success');
  }

  showError(message) {
    if (!message) return;
    // Handle error objects
    const errorMessage = typeof message === 'string' ? message : (message.message || 'An error occurred');
    this.dispatchToast(errorMessage, 'error');
  }

  dispatchToast(notificationHtmlOrMessage, type = 'success') {
    let notificationHtml = notificationHtmlOrMessage;

    // If it's a plain message string, create notification HTML
    if (!notificationHtmlOrMessage || (typeof notificationHtmlOrMessage === 'string' && !notificationHtmlOrMessage.includes('data-toast-target'))) {
      const bgColor = type === 'success'
        ? 'bg-[#FFFFFF] border-[#E3E3E3] border-l-4 border-l-[#5C3984]'
        : 'bg-[#FFFFFF] border-[#E3E3E3] border-l-4 border-l-red-500';

      const icon = type === 'success'
        ? '<svg class="w-5 h-5 text-[#5C3984]" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/></svg>'
        : '<svg class="w-5 h-5 text-red-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/></svg>';

      notificationHtml = `
        <div 
          data-toast-target="notification"
          class="${bgColor} rounded-lg shadow-lg p-4 flex items-start gap-3 transform opacity-0 translate-x-full transition ease-out duration-300"
        >
          ${icon}
          <div class="flex-1 text-sm text-[#0D1120] font-medium">
            ${notificationHtmlOrMessage || 'Operation completed'}
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

    // Dispatch custom event for toast controller to handle
    const event = new CustomEvent('toast:show', {
      detail: { notificationHtml },
      bubbles: true
    });
    document.dispatchEvent(event);
  }

  // Helper functions for formatting and building HTML
  truncateText(text, length) {
    if (!text) return '';
    return text.length > length ? text.substring(0, length) + '...' : text;
  }

  formatSource(source) {
    if (!source) return '-';
    return source.split('_').map(word => word.charAt(0).toUpperCase() + word.slice(1)).join(' ');
  }

  formatDate(dateString) {
    if (!dateString) return '-';
    const date = new Date(dateString);
    return date.toISOString().split('T')[0];
  }

  getStatusStyle(status, dueDate = null) {
    const styles = {
      'open': { bg: 'bg-[#FEF0FF]', text: 'text-[#B130AC]', label: 'Open' },
      'assigned': { bg: 'bg-[#E9F5F8]', text: 'text-[#1B94AD]', label: 'Assigned' },
      'in_progress': { bg: 'bg-[#E9F0FF]', text: 'text-[#1751A7]', label: 'In Progress' },
      'closed': { bg: 'bg-[#E0F9DE]', text: 'text-[#3F9011]', label: 'Closed' }
    };

    // Special cases for in_progress status
    if (status === 'in_progress') {
      if (!dueDate) {
        // No due date means not overdue, so show "In Time"
        return { bg: 'bg-[#F5FFD8]', text: 'text-[#789C16]', label: 'In Time' };
      } else {
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const due = new Date(dueDate);
        due.setHours(0, 0, 0, 0);
        const isOverdue = due < today;

        if (isOverdue) {
          return { bg: 'bg-[#FFF1F0]', text: 'text-[#B13030]', label: 'Overdue' };
        } else {
          return { bg: 'bg-[#F5FFD8]', text: 'text-[#789C16]', label: 'In Time' };
        }
      }
    }

    return styles[status] || { bg: 'bg-gray-100', text: 'text-gray-600', label: status ? status.charAt(0).toUpperCase() + status.slice(1).replace('_', ' ') : '-' };
  }

  getPriorityColor(priority) {
    const colors = {
      'high': 'bg-[#EA4034]',
      'medium': 'bg-[#EC71DD]',
      'low': 'bg-[#64A3EB]'
    };
    return colors[priority] || 'bg-gray-400';
  }

  renderAssigneesHTML(assignees, totalAssignees) {
    if (!assignees || totalAssignees === 0) {
      return '<span class="text-sm text-[#797C81]">-</span>';
    }

    if (totalAssignees <= 2) {
      // Show names when 2 or fewer
      return assignees.map((assignee, index) => {
        const comma = index < assignees.length - 1 ? '<span class="text-sm text-[#797C81]">,</span>' : '';
        return `<span class="text-sm text-[#0D1120]">${this.escapeHtml(assignee.name)}</span>${comma}`;
      }).join(' ');
    } else {
      // Show avatars when more than 2
      const avatars = assignees.map(assignee =>
        `<div class="w-6 h-6 rounded-full bg-[#E3E3E3] flex items-center justify-center text-xs text-[#0D1120] font-medium" title="${this.escapeHtml(assignee.name)}">${assignee.initial}</div>`
      ).join('');
      const moreText = totalAssignees > 3 ? `<span class="text-xs text-[#797C81] font-medium">+${totalAssignees - 3} more</span>` : '';
      return `${avatars}${moreText}`;
    }
  }

  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  buildListRowHTML(capa, assignees, totalAssignees, standardDisplayName, isArchives = false) {
    const statusStyle = this.getStatusStyle(capa.status, capa.due_date);
    const priorityColor = this.getPriorityColor(capa.priority);
    const assigneesHTML = this.renderAssigneesHTML(assignees, totalAssignees);
    const archiveButtonText = isArchives ? 'Unarchive' : 'Archive';
    const archiveButtonOnclick = isArchives ? `unarchiveCapa('${capa.id}')` : `archiveCapa('${capa.id}')`;

    return `
      <tr class="border-b border-[#E3E3E3] hover:bg-[#F7F7FD] cursor-pointer" data-capa-id="${capa.id}">
        <td class="p-4" onclick="event.stopPropagation();">
          <input type="checkbox" class="rounded border-gray-300 text-[#5C3984] focus:ring-[#5C3984]" data-capas--select-all-target="item" data-action="change->capas--select-all#syncMaster" data-capa-id="${capa.id}">
        </td>
        <td class="p-4">
          <div class="flex flex-col">
            <span class="text-sm font-semibold text-[#0D1120]">${this.escapeHtml(this.truncateText(capa.title, 30))}</span>
            <span class="text-xs text-[#797C81] mt-1">${this.escapeHtml(this.truncateText(capa.description, 40))}</span>
          </div>
        </td>
        <td class="p-4">
          <span class="text-sm text-[#0D1120]">${this.escapeHtml(this.formatSource(capa.source))}</span>
        </td>
        <td class="p-4">
          <span class="text-sm text-[#0D1120]">${this.escapeHtml(standardDisplayName || '-')}</span>
        </td>
        <td class="p-4">
          <div class="flex items-center space-x-2">${assigneesHTML}</div>
        </td>
        <td class="p-4">
          <div class="flex items-center space-x-2">
            <div class="w-3 h-3 rounded-full ${priorityColor}"></div>
            <span class="text-sm text-[#0D1120] font-medium">${capa.priority ? capa.priority.charAt(0).toUpperCase() + capa.priority.slice(1) : '-'}</span>
          </div>
        </td>
        <td class="p-4">
          <span class="text-sm text-[#0D1120]">${capa.due_date ? this.formatDate(capa.due_date) : '-'}</span>
        </td>
        <td class="p-4">
          <span class="text-xs px-4 py-1 rounded-full font-medium ${statusStyle.bg} ${statusStyle.text}">${statusStyle.label}</span>
        </td>
        <td class="p-4" onclick="event.stopPropagation();">
          <details class="relative" data-controller="capas--dropdown">
            <summary class="list-none text-[#797C81] hover:text-[#0D1120] cursor-pointer">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 5v.01M12 12v.01M12 19v.01M12 6a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2z" />
              </svg>
            </summary>
            <div class="absolute right-0 mt-2 w-40 bg-white border border-[#E3E3E3] rounded-xl shadow z-[9999] py-1" data-capas--dropdown-target="menu">
              <button type="button" class="block w-full text-left px-3 py-2 text-sm text-[#0D1120] hover:bg-[#F7F7F7] rounded-lg"
                      onclick="openEditCapaModal(this.dataset)"
                      data-capa-id="${capa.id}"
                      data-capa-title="${this.escapeHtml(capa.title)}"
                      data-capa-description="${this.escapeHtml(capa.description)}"
                      data-capa-source="${capa.source}"
                      data-capa-standard-id="${capa.standard_id || ''}"
                      data-capa-priority="${capa.priority || ''}"
                      data-capa-due-date="${capa.due_date || ''}"
                      data-capa-status="${capa.status}"
                      data-capa-assignee-ids="${capa.assignee_ids || ''}">
                Edit
              </button>
              <button type="button" 
                      class="block w-full text-left px-3 py-2 text-sm text-[#0D1120] hover:bg-[#F7F7F7] rounded-lg"
                      onclick="${archiveButtonOnclick}">
                ${archiveButtonText}
              </button>
              <button type="button" 
                      class="block w-full text-left px-3 py-2 text-sm text-[#EA4034] hover:bg-[#FFF1F0] rounded-lg"
                      onclick="deleteCapa('${capa.id}')">
                Delete
              </button>
            </div>
          </details>
        </td>
      </tr>
    `;
  }

  buildBoardCardHTML(capa, assignees, totalAssignees, standardDisplayName) {
    const capaCode = capa.friendly_code || `CAPA-${capa.friendly_id || capa.id.toString().padStart(4, '0')}`;
    const priorityColor = this.getPriorityColor(capa.priority);
    const statusStyle = this.getStatusStyle(capa.status, capa.due_date);

    // Calculate progress from CAPA actions only for 'in_progress' status
    let progressPercent = 0;
    let showProgress = false;
    if (capa.status === 'in_progress' && capa.actions) {
      showProgress = true;
      const totalActions = capa.actions.length || 0;
      const doneActions = capa.actions.filter(a => a.status === 'done').length || 0;
      progressPercent = totalActions > 0 ? Math.round((doneActions / totalActions) * 100) : 0;
    }

    // Check if CAPA is overdue (has due_date and it's before today, and status is not 'closed')
    const isOverdue = capa.due_date &&
      new Date(capa.due_date) < new Date(new Date().setHours(0, 0, 0, 0)) &&
      capa.status !== 'closed';

    // Determine progress bar and text colors based on overdue status
    let progressBarColor = 'bg-[#79BE52]'; // green for in time
    let progressTextColor = 'text-[#79BE52]'; // green for in time
    if (isOverdue) {
      progressBarColor = 'bg-[#EA4034]'; // red for overdue
      progressTextColor = 'text-[#EA4034]'; // red for overdue
    }

    // Build assignees HTML
    let assigneesHTML = '';
    if (assignees && totalAssignees > 0) {
      const avatars = assignees.map(a =>
        `<div class="w-6 h-6 rounded-full bg-[#E3E3E3] flex items-center justify-center text-xs text-[#0D1120] font-medium" title="${this.escapeHtml(a.name)}">${a.initial}</div>`
      ).join('');
      const moreBadge = totalAssignees > 3 ? `<div class="w-6 h-6 rounded-full bg-[#F0F0F0] flex items-center justify-center text-[10px] text-[#797C81] font-medium">+${totalAssignees - 3}</div>` : '';
      const names = assignees.map(a => a.name).join(', ');
      const namesText = totalAssignees > 3 ? `${names} and ${totalAssignees - 3} more` : names;
      assigneesHTML = `
        <div class="flex items-center space-x-2">
          <div class="flex items-center -space-x-1">
            ${avatars}${moreBadge}
          </div>
          <span class="text-xs text-[#0D1120] break-words">${this.escapeHtml(namesText)}</span>
        </div>
      `;
    } else {
      assigneesHTML = '<span class="text-xs text-[#0D1120]">-</span>';
    }

    // Format due date
    let dueDateHTML = '-';
    if (capa.due_date) {
      const date = new Date(capa.due_date);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      dueDateHTML = `${months[date.getMonth()]} ${date.getDate()}, ${date.getFullYear()}`;
    }

    // Calculate action counts for data attributes
    const totalActions = capa.actions ? capa.actions.length : 0;
    const doneActions = capa.actions ? capa.actions.filter(a => a.status === 'done').length : 0;

    return `
      <div class="relative overflow-visible border border-[#E3E3E3] rounded-xl p-4 hover:shadow-sm cursor-move select-none"
           draggable="true"
           data-action="mousedown->capas--board#prepareDrag dragstart->capas--board#dragStart dragend->capas--board#dragEnd"
           style="-webkit-user-drag: element;"
           data-capa-id="${capa.id}" data-capa-status="${capa.status}" data-total-actions="${totalActions}" data-done-actions="${doneActions}" data-capa-due-date="${capa.due_date || ''}">
        <div class="flex items-start justify-between">
          <div class="flex-1">
            <div class="inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-medium text-[#5D6B80] bg-[#F2F4F8]">
              ${capaCode}
            </div>
            <div class="text-sm font-semibold text-[#0D1120] mt-2 break-words">${this.escapeHtml(capa.title)}</div>
            <div class="text-xs text-[#797C81] mt-1 break-words">${this.escapeHtml(capa.description)}</div>
          </div>
        </div>

        ${showProgress ? `
        <div class="mt-3">
          <div class="flex items-center justify-between text-xs ${progressTextColor} font-medium">
            <span>Progress:</span>
            <span>${progressPercent}%</span>
          </div>
          <div class="w-full h-1.5 bg-[#E9F0FF] rounded-full mt-1">
            <div class="h-1.5 ${progressBarColor} rounded-full" style="width: ${progressPercent}%"></div>
          </div>
        </div>
        ` : ''}

        <div class="mt-3 flex items-center justify-between">
          ${assigneesHTML}
        </div>

        <div class="mt-3 flex items-center justify-between text-xs text-[#797C81]">
          <div class="flex items-center space-x-3">
            <div class="flex items-center space-x-2 px-2 py-1 rounded-full bg-[#F7F7F7]">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4 text-[#5C3984]"><path stroke-linecap="round" stroke-linejoin="round" d="M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 012.25-2.25h13.5A2.25 2.25 0 0121 7.5v11.25m-18 0A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75m-18 0v-7.5A2.25 2.25 0 015.25 9h13.5A2.25 2.25 0 0121 11.25v7.5"/></svg>
              <span>${dueDateHTML}</span>
            </div>
            <div class="flex items-center space-x-2 px-2 py-1 rounded-full bg-[#F7F7F7]">
              <span class="flex items-center space-x-1">
                <span class="w-2.5 h-2.5 rounded-full ${priorityColor}"></span>
                <span class="text-[#0D1120] font-medium">${capa.priority ? capa.priority.charAt(0).toUpperCase() + capa.priority.slice(1) : '-'}</span>
              </span>
            </div>
          </div>
          <div class="px-2 py-0.5 rounded-full ${statusStyle.bg} ${statusStyle.text} font-medium" data-role="status-badge">
            ${statusStyle.label}
          </div>
        </div>

        <div class="mt-3 flex items-center justify-between w-full">
          <a href="/dashboard/capa_management/${capa.id}#evidence" class="inline-flex items-center justify-center px-4 py-2 gap-2 isolate w-[190px] h-10 bg-white border border-[#E3E3E3] rounded-xl text-xs font-medium text-[#0D1120]" draggable="false" data-turbo="false" onclick="sessionStorage.setItem('capa_management_last_page', window.location.pathname + window.location.search); return true;">
            <span>View</span>
            <svg class="w-4 h-4 fill-[#5C3984]" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true">
              <path d="M21 3a1 1 0 00-1-1h-6a1 1 0 100 2h3.586L4.293 17.293a1 1 0 101.414 1.414L19 5.414V9a1 1 0 102 0V3z" />
            </svg>
          </a>
          <details class="ml-4 relative" data-controller="capas--dropdown" draggable="false">
            <summary class="list-none p-2 rounded-lg text-[#797C81] hover:text-[#0D1120] hover:bg-[#F7F7F7] cursor-pointer" draggable="false">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 5v.01M12 12v.01M12 19v.01M12 6a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2z" />
              </svg>
            </summary>
            <div class="absolute right-0 mt-2 w-40 bg-white border border-[#E3E3E3] rounded-xl shadow z-[9999] py-1" data-capas--dropdown-target="menu">
              <button type="button" class="block w-full text-left px-3 py-2 text-sm text-[#0D1120] hover:bg-[#F7F7F7] rounded-lg"
                      onclick="openEditCapaModal(this.dataset)"
                      data-capa-id="${capa.id}"
                      data-capa-title="${this.escapeHtml(capa.title)}"
                      data-capa-description="${this.escapeHtml(capa.description)}"
                      data-capa-source="${capa.source}"
                      data-capa-standard-id="${capa.standard_id || ''}"
                      data-capa-priority="${capa.priority || ''}"
                      data-capa-due-date="${capa.due_date || ''}"
                      data-capa-status="${capa.status}"
                      data-capa-assignee-ids="${capa.assignee_ids || ''}">
                Edit
              </button>
              <button type="button" 
                      class="block w-full text-left px-3 py-2 text-sm text-[#0D1120] hover:bg-[#F7F7F7] rounded-lg"
                      onclick="archiveCapa('${capa.id}')">
                Archive
              </button>
              <button type="button" 
                      class="block w-full text-left px-3 py-2 text-sm text-[#EA4034] hover:bg-[#FFF1F0] rounded-lg"
                      onclick="deleteCapa('${capa.id}')">
                Delete
              </button>
            </div>
          </details>
        </div>
      </div>
    `;
  }

  detectPageContext() {
    const path = window.location.pathname;
    if (path.includes('/board')) return 'board';
    if (path.includes('/list')) return 'list';
    if (path.includes('/archives')) return 'archives';
    // Overview page is at /dashboard/capa_management (without /list or /board)
    if (path.match(/\/capa_management\/?$/) && !path.includes('/list') && !path.includes('/board')) return 'overview';
    if (path.match(/\/capa_management\/\d+$/)) return 'show';
    return 'unknown';
  }

  getActiveFilters() {
    const urlParams = new URLSearchParams(window.location.search);
    return {
      status: urlParams.get('status') || null,
      priority: urlParams.get('priority') || null,
      assignee_id: urlParams.get('assignee_id') || null,
      due_date_from: urlParams.get('due_date_from') || null,
      due_date_to: urlParams.get('due_date_to') || null
    };
  }

  updateOverviewPage(result) {
    if (!result.overview_stats) return;

    const stats = result.overview_stats;

    // Update summary card counts
    const openCountEl = document.querySelector('[data-overview-stat="open_count"]');
    if (openCountEl) openCountEl.textContent = stats.open_count || 0;

    const highPriorityCountEl = document.querySelector('[data-overview-stat="high_priority_count"]');
    if (highPriorityCountEl) highPriorityCountEl.textContent = stats.high_priority_count || 0;

    const overdueCountEl = document.querySelector('[data-overview-stat="overdue_count"]');
    if (overdueCountEl) overdueCountEl.textContent = stats.overdue_count || 0;

    const avgResolutionEl = document.querySelector('[data-overview-stat="avg_resolution_days"]');
    if (avgResolutionEl) {
      avgResolutionEl.textContent = stats.avg_resolution_days ? `${stats.avg_resolution_days} days` : '0 days';
    }

    // Update "Assigned to Me" table if row provided
    if (result.assigned_to_me_row) {
      const assignedTable = document.querySelector('[data-overview-table="assigned_to_me"]');
      if (assignedTable) {
        // Remove empty state if exists
        const emptyRow = assignedTable.querySelector('tr[colspan]');
        if (emptyRow) emptyRow.remove();

        // Insert new row at the top
        const temp = document.createElement('tbody');
        temp.innerHTML = result.assigned_to_me_row.trim();
        const newRow = temp.firstElementChild;
        if (newRow) {
          assignedTable.insertBefore(newRow, assignedTable.firstChild);

          // Limit to 4 rows
          const rows = assignedTable.querySelectorAll('tr:not([colspan])');
          if (rows.length > 4) {
            rows[rows.length - 1].remove();
          }
        }
      }
    }

    // Update "Overdue" table if row provided
    if (result.overdue_row) {
      const overdueTable = document.querySelector('[data-overview-table="overdue"]');
      if (overdueTable) {
        // Remove empty state if exists
        const emptyRow = overdueTable.querySelector('tr[colspan]');
        if (emptyRow) emptyRow.remove();

        // Insert new row at the top
        const temp = document.createElement('tbody');
        temp.innerHTML = result.overdue_row.trim();
        const newRow = temp.firstElementChild;
        if (newRow) {
          overdueTable.insertBefore(newRow, overdueTable.firstChild);

          // Limit to 4 rows
          const rows = overdueTable.querySelectorAll('tr:not([colspan])');
          if (rows.length > 4) {
            rows[rows.length - 1].remove();
          }
        }
      }
    }
  }

  shouldInsertCAPAInList(capa) {
    if (!capa) return false;

    const filters = this.getActiveFilters();

    // Check status filter
    if (filters.status && filters.status !== 'all') {
      if (filters.status === 'overdue') {
        // For overdue filter, check if CAPA is overdue
        if (!capa.due_date) return false;
        const dueDate = new Date(capa.due_date);
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        if (dueDate >= today || capa.status === 'closed') return false;
      } else {
        // Exact status match
        if (capa.status !== filters.status) return false;
      }
    }

    // Check priority filter
    if (filters.priority && capa.priority !== filters.priority) {
      return false;
    }

    // Check assignee filter
    if (filters.assignee_id) {
      const assigneeIds = (capa.assignee_ids || '').split(',').map(id => id.trim()).filter(Boolean);
      if (!assigneeIds.includes(filters.assignee_id)) {
        return false;
      }
    }

    // Check due date filters
    if (filters.due_date_from) {
      if (!capa.due_date) {
        // If filter requires a due date but CAPA has none, don't match
        return false;
      }
      const capaDueDate = new Date(capa.due_date);
      const filterFromDate = new Date(filters.due_date_from);
      filterFromDate.setHours(0, 0, 0, 0);
      if (capaDueDate < filterFromDate) {
        return false;
      }
    }

    if (filters.due_date_to) {
      if (!capa.due_date) {
        // If filter requires a due date but CAPA has none, don't match
        return false;
      }
      const capaDueDate = new Date(capa.due_date);
      const filterToDate = new Date(filters.due_date_to);
      filterToDate.setHours(23, 59, 59, 999);
      if (capaDueDate > filterToDate) {
        return false;
      }
    }

    // If no filters are active, or all filters match, insert the CAPA
    return true;
  }

  updateUIAfterCreate(result) {
    const context = this.detectPageContext();

    if (!result.capa) {
      console.warn('updateUIAfterCreate: Missing capa data in result', result);
      return;
    }

    const capa = result.capa;
    const assignees = result.assignees || [];
    const totalAssignees = result.total_assignees || 0;
    const standardDisplayName = result.standard_display_name || null;

    if (context === 'board') {
      // Build card HTML in JavaScript
      const cardHTML = this.buildBoardCardHTML(capa, assignees, totalAssignees, standardDisplayName);
      const status = capa.status || 'open';
      const column = document.querySelector(`[data-capas--board-target="column"][data-status="${status}"]`);
      if (column) {
        const cardsContainer = column.querySelector('[data-role="cards"]');
        if (cardsContainer) {
          const temp = document.createElement('div');
          temp.innerHTML = cardHTML.trim();
          const newCard = temp.firstElementChild;
          if (newCard) {
            cardsContainer.insertBefore(newCard, cardsContainer.firstChild);
            // Update counts - dispatch event for board controller
            const updateEvent = new CustomEvent('capa:counts-update', { bubbles: true });
            document.dispatchEvent(updateEvent);
            // Hide empty state
            const emptyState = column.querySelector('[data-role="empty"]');
            if (emptyState) emptyState.classList.add('hidden');
          }
        }
      }
    } else if (context === 'list' || context === 'archives') {
      // Check if CAPA matches current filters before inserting
      if (this.shouldInsertCAPAInList(capa)) {
        // Build row HTML in JavaScript
        const rowHTML = this.buildListRowHTML(capa, assignees, totalAssignees, standardDisplayName, context === 'archives');
        const table = document.querySelector('table[data-controller="capas--select-all"]');
        if (table) {
          const tbody = table.querySelector('tbody');
          if (tbody) {
            // Remove empty state row if it exists
            const emptyRow = tbody.querySelector('tr td[colspan]');
            if (emptyRow) {
              emptyRow.closest('tr').remove();
            }

            // Insert new row at the top
            const temp = document.createElement('tbody');
            temp.innerHTML = rowHTML.trim();
            const newRow = temp.firstElementChild;
            if (newRow) {
              tbody.insertBefore(newRow, tbody.firstChild);
            }
          }
        }
      }
      // If CAPA doesn't match filters, toast will still show but row won't be added
    } else if (context === 'overview' && capa) {
      // Update overview page dynamically
      this.updateOverviewPage(result);
      // Refresh the page after 1 second to update charts and most assigned CAPA list
      setTimeout(() => {
        window.location.reload();
      }, 1000);
    } else if (context === 'show') {
      // On detail page, do nothing - new CAPA shouldn't appear here
      // Optionally redirect to list
      window.location.href = '/dashboard/capa_management/list';
    } else {
      // Fallback: do nothing if we can't determine context
    }
  }
}

