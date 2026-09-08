import { Controller } from "@hotwired/stimulus";
import Choices from "choices.js";

// Controls the Edit CAPA modal: populate fields and submit PATCH
export default class extends Controller {
  static targets = ["assignedUsers", "userSelect", "statusSelect"];
  static values = { deleteIconPath: String };

  connect() {
    this.choices = null;
    this.initChoices();
  }

  disconnect() {
    if (this.choices) {
      this.choices.destroy();
      this.choices = null;
    }
  }

  initChoices() {
    if (this.choices || !this.userSelectTarget) return;

    this.choices = new Choices(this.userSelectTarget, {
      allowHTML: true,
      removeItemButton: true,
      searchEnabled: true,
      placeholder: true,
      placeholderValue: "Select User",
      itemSelectText: '',
      shouldSort: false,
      callbackOnCreateTemplates: (template) => {
        return {
          choice: (classNames, data) => {
            const props = data.customProperties || {};
            // Parse dataset properties if customProperties are empty
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


    this.userSelectTarget.closest('.choices').querySelector('.choices__list--multiple').style.display = 'none';

    // Listen for changes
    this.userSelectTarget.addEventListener('change', () => this.updateChipList());
    this.userSelectTarget.addEventListener('addItem', () => this.updateChipList());
    this.userSelectTarget.addEventListener('removeItem', () => this.updateChipList());
  }

  // Re-renders every Choices-backed select in a container from its current
  // value. Applied to the whole modal rather than to one field, because the
  // same mismatch would appear on any of them.
  syncEnhancedSelects(container) {
    container.querySelectorAll('[data-choices-select-target="select"]').forEach((select) => {
      const wrapper = select.closest('[data-controller~="choices-select"]');
      (wrapper || select).dispatchEvent(new CustomEvent("choices:sync", { bubbles: true }));
    });
  }

  open(event) {
    const el = event.currentTarget;
    const modal = document.getElementById('editActionModal');
    if (!modal) return;

    // Reset form state
    this.resetFormState();

    // Populate fields
    modal.querySelector('[data-field="capaId"]').value = el.dataset.capaId;
    modal.querySelector('[data-field="title"]').value = el.dataset.capaTitle || '';
    modal.querySelector('[data-field="description"]').value = el.dataset.capaDescription || '';
    modal.querySelector('[data-field="source"]').value = el.dataset.capaSource || '';
    modal.querySelector('[data-field="standardId"]').value = el.dataset.capaStandardId || '';
    modal.querySelector('[data-field="priority"]').value = el.dataset.capaPriority || '';
    modal.querySelector('[data-field="dueDate"]').value = el.dataset.capaDueDate || '';

    const statusField = modal.querySelector('[data-field="status"]');
    const statusValue = el.dataset.capaStatus || 'open';
    statusField.value = statusValue;

    if (this.hasStatusSelectTarget) {
      this.statusSelectTarget.value = statusValue;
    }

    this.originalStatus = statusValue;
    this.lastStatusValue = statusValue;

    // The enhanced selects render their own widget, so assigning .value above is
    // not enough — without this the modal shows one value and saves another.
    this.syncEnhancedSelects(modal);

    // Set assigned users in Choices
    if (this.choices) {
      const idsRaw = el.dataset.capaAssigneeIds || '';
      const assignedUserIds = idsRaw.split(',').map(s => s.trim()).filter(Boolean);

      if (assignedUserIds.length > 0) {
        this.choices.setChoiceByValue(assignedUserIds);
      }

      // Force update chips immediately
      this.updateChipList();
    }

    modal.showModal();
  }

  updateChipList() {
    if (!this.hasAssignedUsersTarget) return;

    const selectedItems = this.choices.getValue();
    this.assignedUsersTarget.innerHTML = '';

    if (selectedItems.length === 0) return;

    selectedItems.forEach(item => {
      const props = item.customProperties || {};
      if (Object.keys(props).length === 0 && item.element) {
        Object.assign(props, item.element.dataset);
      }

      const name = props.name || item.label;
      const role = props.role || '';
      const avatarUrl = props.profileImageUrl;
      const initial = name ? name.charAt(0).toUpperCase() : '?';

      const chip = document.createElement('div');
      chip.className = 'flex items-center gap-3 h-12 px-3 border border-[#E3E3E3] rounded-xl user-chip bg-[#F7F7FD]';
      chip.dataset.userId = item.value;

      const avatarHtml = avatarUrl
        ? `<img src="${avatarUrl}" class="w-7 h-7 rounded-full object-cover flex-shrink-0">`
        : `<div class="w-7 h-7 rounded-full bg-[#D6C4ED] flex items-center justify-center text-xs font-semibold text-[#5C3984] flex-shrink-0">${initial}</div>`;

      // Fallback for delete icon if not in values (reuse from modal or window)
      const modal = document.getElementById("editActionModal");
      const form = modal ? modal.querySelector("form") : null;
      const deleteIconPath = form?.getAttribute("data-capas--edit-form-delete-icon-path-value") || this.deleteIconPathValue || (window.assetPaths && window.assetPaths.deleteIcon) || "";

      chip.innerHTML = `
        <div class="flex items-center gap-2 min-w-0 flex-1">
          ${avatarHtml}
          <span class="text-sm text-[#0D1120] truncate font-medium">${this.escapeHtml(name)}</span>
          <span class="text-xs text-[#797C81] flex-shrink-0 bg-white px-2 py-0.5 rounded-full border border-[#E3E3E3]">${this.escapeHtml(role)}</span>
        </div>
        <button type="button" class="text-[#797C81] hover:text-[#EA4034] transition-colors flex-shrink-0 p-1" data-action="click->capas--edit-form#removeUser" data-value="${item.value}">
           <img src="${deleteIconPath}" class="w-4 h-4" alt="Remove name" />
        </button>
      `;
      this.assignedUsersTarget.appendChild(chip);
    });
  }

  removeUser(event) {
    const button = event.currentTarget;
    const value = button.dataset.value;
    if (value) {
      this.choices.removeActiveItemsByValue(value);
    }
  }

  removeAllAssignedUsers() {
    if (this.choices) {
      this.choices.removeActiveItems();
    }
  }

  resetFormState() {
    if (this.choices) {
      this.choices.removeActiveItems();
    }
    if (this.assignedUsersTarget) {
      this.assignedUsersTarget.innerHTML = "";
    }
    this.originalStatus = null;
    this.lastStatusValue = null;

    // Note: we don't need to manually remove hidden inputs anymore 
    // because Choices + FormData handles the submission state.
  }

  async submitForm(event) {
    event.preventDefault();

    const form = event.currentTarget.tagName === 'FORM' ? event.currentTarget : event.target;
    const formData = new FormData(form);
    const capaId = formData.get("id");

    let submitButton = event.submitter;
    if (!submitButton && form.id) {
      submitButton = document.querySelector(`button[type="submit"][form="${form.id}"]`);
    }
    if (!submitButton) {
      submitButton = form.querySelector('button[type="submit"]');
    }

    const originalContent = submitButton ? submitButton.innerHTML : "";

    try {
      if (submitButton) {
        const span = submitButton.querySelector('span');
        if (span) {
          span.textContent = "Saving...";
        } else {
          submitButton.textContent = "Saving...";
        }
        submitButton.disabled = true;
      }

      const response = await fetch(`/dashboard/capa_management/${capaId}`, {
        method: "PATCH",
        body: formData,
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Accept": "application/json"
        },
      });

      if (response.ok) {
        const result = await response.json();

        if (result.notification_html) {
          this.dispatchToast(result.notification_html);
        } else {
          this.showSuccess(result.message || "CAPA updated successfully!");
        }

        const modal = document.getElementById('editActionModal');
        if (modal) modal.close();

        this.updateUIAfterEdit(result, capaId);
      } else {
        const error = await response.json();
        if (error.notification_html) {
          this.dispatchToast(error.notification_html, 'error');
        } else {
          this.showError(error.message || "CAPA update failed. Please try again.");
        }
      }
    } catch (error) {
      console.error("CAPA update error:", error);
      this.showError("An unexpected error occurred.");
    } finally {
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
    const errorMessage = typeof message === 'string' ? message : (message.message || 'An error occurred');
    this.dispatchToast(errorMessage, 'error');
  }

  dispatchToast(notificationHtmlOrMessage, type = 'success') {
    let notificationHtml = notificationHtmlOrMessage;

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

    const event = new CustomEvent('toast:show', {
      detail: { notificationHtml },
      bubbles: true
    });
    document.dispatchEvent(event);
  }

  // kept for compatibility if referenced elsewhere
  createUserChip(userId, userName, userRole, profileImageUrl) {
    return document.createElement('div');
  }

  // ... keep other helpers ...
  addUser(event) {
    // Deprecated manual add, choices handles this
    event.preventDefault();
  }

  removeUserById(userId, chipElement = null) {
    // Deprecated, choices handles this
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
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
    const safeAssignees = Array.isArray(assignees) ? assignees : [];
    const totalAssigneeCount = typeof totalAssignees === 'number' ? totalAssignees : safeAssignees.length;
    const assigneeNamesJson = JSON.stringify(safeAssignees.map(a => a.name || ''));
    const assigneeRolesJson = JSON.stringify(safeAssignees.map(a => a.role || ''));
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

    // Build assignees HTML matching server-rendered card
    let assigneeChipsHTML = '';
    let assigneeNamesText = '-';
    if (safeAssignees.length > 0) {
      assigneeChipsHTML = safeAssignees.map(a =>
        `<div class="w-6 h-6 rounded-full bg-[#E3E3E3] flex items-center justify-center text-xs text-[#0D1120] font-medium" title="${this.escapeHtml(a.name)}">${a.initial}</div>`
      ).join('');

      const remainingCount = Math.max(totalAssigneeCount - safeAssignees.length, 0);
      if (remainingCount > 0) {
        assigneeChipsHTML += `<div class="w-6 h-6 rounded-full bg-[#F0F0F0] flex items-center justify-center text-[10px] text-[#797C81] font-medium">+${remainingCount}</div>`;
      }

      const displayedNames = safeAssignees.map(a => a.name).join(', ');
      assigneeNamesText = remainingCount > 0
        ? `${displayedNames}${displayedNames ? ' and ' : ''}${remainingCount} more`
        : displayedNames;
      assigneeNamesText = assigneeNamesText || '-';
    }

    const assigneesHTML = `
      <div class="flex items-center space-x-2">
        <div class="flex items-center -space-x-1" data-role="assignee-chips">
          ${assigneeChipsHTML}
        </div>
        <span class="text-xs text-[#0D1120] break-words" data-role="assignee-names">
          ${this.escapeHtml(assigneeNamesText)}
        </span>
      </div>
    `;

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
      <div class="border border-[#E3E3E3] rounded-xl p-4 hover:shadow-sm cursor-move select-none"
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
                      data-capa-assignee-ids="${capa.assignee_ids || ''}"
                      data-capa-assignee-names='${this.escapeHtml(assigneeNamesJson)}'
                      data-capa-assignee-roles='${this.escapeHtml(assigneeRolesJson)}'>
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
    // Show page: check for show page elements or UUID pattern
    if (document.getElementById('capa-title') || document.getElementById('capa-status-badge')) {
      return 'show';
    }
    // Fallback: check URL pattern for UUID (more flexible than strict 36 chars)
    if (path.match(/\/capa_management\/[a-f0-9-]+$/i)) return 'show';
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
        // Check if CAPA already exists in table
        const existingRow = Array.from(assignedTable.querySelectorAll('tr')).find(tr => {
          const titleCell = tr.querySelector('td:first-child span');
          return titleCell && titleCell.textContent.trim() === result.capa.title.substring(0, 40);
        });

        if (existingRow) {
          // Update existing row
          const temp = document.createElement('tbody');
          temp.innerHTML = result.assigned_to_me_row.trim();
          const newRow = temp.firstElementChild;
          if (newRow) {
            existingRow.replaceWith(newRow);
          }
        } else {
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
    }

    // Update "Overdue" table if row provided
    if (result.overdue_row) {
      const overdueTable = document.querySelector('[data-overview-table="overdue"]');
      if (overdueTable) {
        // Check if CAPA already exists in table
        const existingRow = Array.from(overdueTable.querySelectorAll('tr')).find(tr => {
          const titleCell = tr.querySelector('td:first-child span');
          return titleCell && titleCell.textContent.trim() === result.capa.title.substring(0, 40);
        });

        if (existingRow) {
          // Update existing row
          const temp = document.createElement('tbody');
          temp.innerHTML = result.overdue_row.trim();
          const newRow = temp.firstElementChild;
          if (newRow) {
            existingRow.replaceWith(newRow);
          }
        } else {
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
  }

  updateShowPage(result) {
    if (!result.show_page_html || !result.capa) {
      console.warn('updateShowPage: Missing show_page_html or capa in result', result);
      return;
    }

    const html = result.show_page_html;

    // Update status badge
    const statusBadge = document.getElementById('capa-status-badge');
    if (statusBadge && html.status_html) {
      statusBadge.textContent = html.status_html;
      statusBadge.className = `inline-flex items-center justify-center px-4 py-1 rounded-full text-sm font-medium ${html.status_bg} ${html.status_text}`;
      statusBadge.style.height = '28px';
    }

    // Update due date
    const dueDateContainer = document.getElementById('capa-due-date-container');
    if (dueDateContainer) {
      if (html.due_date_html) {
        // Update the span with the new date
        const span = dueDateContainer.querySelector('span');
        if (span) {
          span.textContent = `Due ${html.due_date_html}`;
        } else {
          // If span doesn't exist, create the full structure
          dueDateContainer.innerHTML = `
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4 text-[#5C3984]"><path stroke-linecap="round" stroke-linejoin="round" d="M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 012.25-2.25h13.5A2.25 2.25 0 0121 7.5v11.25m-18 0A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75m-18 0v-7.5A2.25 2.25 0 015.25 9h13.5A2.25 2.25 0 0121 11.25v7.5"/></svg>
            <span>Due ${html.due_date_html}</span>
          `;
        }
        dueDateContainer.style.display = '';
      } else {
        dueDateContainer.style.display = 'none';
      }
    }

    // Update priority
    const priorityContainer = document.getElementById('capa-priority-container');
    if (priorityContainer && html.priority_html) {
      const span = priorityContainer.querySelector('span');
      if (span) {
        span.textContent = html.priority_html;
      }
    }

    // Update source/audit
    const sourceContainer = document.getElementById('capa-source-container');
    if (sourceContainer && html.source_html) {
      const span = sourceContainer.querySelector('span');
      if (span) {
        span.textContent = html.source_html;
      }
    }

    // Update CAPA code
    const capaCodeContainer = document.getElementById('capa-code-container');
    if (capaCodeContainer && html.capa_code_html) {
      const span = capaCodeContainer.querySelector('span');
      if (span) {
        span.textContent = html.capa_code_html;
      }
    }

    // Update standard
    const standardContainer = document.getElementById('capa-standard-container');
    if (standardContainer) {
      if (html.standard_html) {
        const span = standardContainer.querySelector('span');
        if (span) {
          span.textContent = html.standard_html;
        }
        standardContainer.style.display = '';
      } else {
        standardContainer.style.display = 'none';
      }
    }

    // Update title
    const titleEl = document.getElementById('capa-title');
    if (titleEl && html.title_html) {
      titleEl.textContent = html.title_html;
    }

    // Update description
    const descriptionEl = document.getElementById('capa-description');
    if (descriptionEl && html.description_html) {
      descriptionEl.textContent = html.description_html;
    }

    // Update assignees
    const assigneesContainer = document.getElementById('capa-assignees-container');
    if (assigneesContainer && html.assignees) {
      if (html.assignees.length > 0) {
        const assigneesHtml = `
          <div class="flex items-center gap-2">
            <div class="flex items-center" style="isolation: isolate;">
              ${html.assignees.slice(0, 3).map((assignee, index) => `
                <div class="w-7 h-7 rounded-full bg-[#E3E3E3] flex items-center justify-center text-xs text-[#0D1120] font-medium border-2 border-white" 
                     style="margin-left: ${index > 0 ? '-8px' : '0'}; z-index: ${3 - index};"
                     title="${assignee.name}">
                  ${assignee.initial}
                </div>
              `).join('')}
            </div>
            <span class="text-xs font-medium text-[#797C81]">
              ${html.assignees.slice(0, 3).map(a => a.name).join(', ')}
              ${html.assignees.length > 3 ? ` + ${html.assignees.length - 3} more` : ''}
            </span>
          </div>
        `;
        assigneesContainer.innerHTML = assigneesHtml;
        assigneesContainer.style.display = '';
      } else {
        assigneesContainer.style.display = 'none';
      }
    }
  }

  shouldShowCAPAInList(capa) {
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

    // If no filters are active, or all filters match, show the CAPA
    return true;
  }

  updateUIAfterEdit(result, capaId) {
    const context = this.detectPageContext();

    if (!result.capa) {
      console.warn('updateUIAfterEdit: Missing capa data in result', result);
      return;
    }

    const capa = result.capa;
    const assignees = result.assignees || [];
    const totalAssignees = result.total_assignees || 0;
    const standardDisplayName = result.standard_display_name || null;

    if (context === 'board') {
      // Build card HTML in JavaScript
      const cardHTML = this.buildBoardCardHTML(capa, assignees, totalAssignees, standardDisplayName);
      const existingCard = document.querySelector(`[data-capa-id="${capaId}"]`);

      if (existingCard) {
        const temp = document.createElement('div');
        temp.innerHTML = cardHTML.trim();
        const newCard = temp.firstElementChild;

        if (newCard) {
          // Check if status changed - if so, move to new column
          const oldStatus = existingCard.dataset.capaStatus;
          const newStatus = capa.status;

          if (oldStatus !== newStatus) {
            // Move to new column
            const newColumn = document.querySelector(`[data-capas--board-target="column"][data-status="${newStatus}"]`);
            if (newColumn) {
              const cardsContainer = newColumn.querySelector('[data-role="cards"]');
              if (cardsContainer) {
                existingCard.remove();
                cardsContainer.insertBefore(newCard, cardsContainer.firstChild);
              }
            }
            // Update counts - dispatch event for board controller
            const updateEvent = new CustomEvent('capa:counts-update', { bubbles: true });
            document.dispatchEvent(updateEvent);

            // Handle empty states
            const oldColumn = document.querySelector(`[data-capas--board-target="column"][data-status="${oldStatus}"]`);
            if (oldColumn) {
              const oldCards = oldColumn.querySelectorAll('[data-role="cards"] [data-capa-id]');
              const emptyStateOld = oldColumn.querySelector('[data-role="empty"]');
              if (oldCards.length === 0 && emptyStateOld) {
                emptyStateOld.classList.remove('hidden');
              }
            }
            const newStatusColumn = document.querySelector(`[data-capas--board-target="column"][data-status="${newStatus}"]`);
            if (newStatusColumn) {
              const emptyStateNew = newStatusColumn.querySelector('[data-role="empty"]');
              if (emptyStateNew) emptyStateNew.classList.add('hidden');
            }
          } else {
            // Same column, just replace
            existingCard.replaceWith(newCard);
            // Update counts even when status doesn't change
            const updateEvent = new CustomEvent('capa:counts-update', { bubbles: true });
            document.dispatchEvent(updateEvent);
          }
        }
      }
    } else if (context === 'list' || context === 'archives') {
      // Update DOM cells directly
      const matchesFilters = this.shouldShowCAPAInList(capa);
      const existingRow = document.querySelector(`tr[data-capa-id="${capaId}"]`);

      if (matchesFilters) {
        if (existingRow) {
          // Update existing row cells directly
          this.updateListRowCells(existingRow, capa, assignees, totalAssignees, standardDisplayName, context === 'archives');
        } else {
          // Row doesn't exist but should be shown (was filtered out before, now matches)
          const table = document.querySelector('table[data-controller="capas--select-all"]');
          if (table) {
            const tbody = table.querySelector('tbody');
            if (tbody) {
              // Remove empty state if it exists
              const emptyRow = tbody.querySelector('tr td[colspan]');
              if (emptyRow) {
                emptyRow.closest('tr').remove();
              }
              // Build and insert new row
              const rowHTML = this.buildListRowHTML(capa, assignees, totalAssignees, standardDisplayName, context === 'archives');
              const temp = document.createElement('tbody');
              temp.innerHTML = rowHTML.trim();
              const newRow = temp.firstElementChild;
              if (newRow) {
                tbody.insertBefore(newRow, tbody.firstChild);
              }
            }
          }
        }
      } else {
        // CAPA no longer matches filters, remove it from the list
        if (existingRow) {
          existingRow.remove();
          // Check if table is now empty and show empty state
          const table = document.querySelector('table[data-controller="capas--select-all"]');
          if (table) {
            const tbody = table.querySelector('tbody');
            if (tbody && tbody.children.length === 0) {
              const emptyStateHtml = `
                <tr>
                  <td colspan="9" class="p-8 text-center text-[#797C81]">
                    No CAPAs found. <a href="#" class="text-[#5C3984] underline" onclick="document.getElementById('newActionModal').showModal(); return false;">Create your first CAPA</a> to get started.
                  </td>
                </tr>
              `;
              const temp = document.createElement('tbody');
              temp.innerHTML = emptyStateHtml.trim();
              const emptyRow = temp.firstElementChild;
              if (emptyRow) {
                tbody.appendChild(emptyRow);
              }
            }
          }
        }
      }
      // Update edit button data attributes for future edits
      const editButton = document.querySelector(`[onclick*="openEditCapaModal"][data-capa-id="${capaId}"]`);
      if (editButton) {
        editButton.dataset.capaTitle = capa.title || '';
        editButton.dataset.capaDescription = capa.description || '';
        editButton.dataset.capaSource = capa.source || '';
        editButton.dataset.capaStandardId = capa.standard_id || '';
        editButton.dataset.capaPriority = capa.priority || '';
        editButton.dataset.capaDueDate = capa.due_date || '';
        editButton.dataset.capaStatus = capa.status || '';
        editButton.dataset.capaAssigneeIds = capa.assignee_ids || '';
      }
    } else if (context === 'show' && capa) {
      // Update edit button data attributes
      const editButton = document.querySelector(`[onclick*="openEditCapaModal"][data-capa-id="${capaId}"]`);
      if (editButton) {
        editButton.dataset.capaTitle = capa.title || '';
        editButton.dataset.capaDescription = capa.description || '';
        editButton.dataset.capaSource = capa.source || '';
        editButton.dataset.capaStandardId = capa.standard_id || '';
        editButton.dataset.capaPriority = capa.priority || '';
        editButton.dataset.capaDueDate = capa.due_date || '';
        editButton.dataset.capaStatus = capa.status || '';
        editButton.dataset.capaAssigneeIds = capa.assignee_ids || '';
      }
      // Reload page to show updated details (show page has complex content)
      this.updateShowPage(result);
    } else if (context === 'overview' && capa) {
      // Update overview page dynamically
      this.updateOverviewPage(result);
    }
  }

  updateListRowCells(row, capa, assignees, totalAssignees, standardDisplayName, isArchives = false) {
    const cells = row.querySelectorAll('td');
    if (cells.length < 9) return; // Ensure we have all cells

    // Cell 0: Checkbox (keep as is)

    // Cell 1: Title & Description
    const titleDescCell = cells[1];
    const titleSpan = titleDescCell.querySelector('span:first-child');
    const descSpan = titleDescCell.querySelector('span:last-child');
    if (titleSpan) titleSpan.textContent = this.truncateText(capa.title, 30);
    if (descSpan) descSpan.textContent = this.truncateText(capa.description, 40);

    // Cell 2: Source
    const sourceCell = cells[2];
    const sourceSpan = sourceCell.querySelector('span');
    if (sourceSpan) sourceSpan.textContent = this.formatSource(capa.source);

    // Cell 3: Standard
    const standardCell = cells[3];
    const standardSpan = standardCell.querySelector('span');
    if (standardSpan) standardSpan.textContent = standardDisplayName || '-';

    // Cell 4: Assignees
    const assigneesCell = cells[4];
    const assigneesContainer = assigneesCell.querySelector('div');
    if (assigneesContainer) {
      assigneesContainer.innerHTML = this.renderAssigneesHTML(assignees, totalAssignees);
    }

    // Cell 5: Priority
    const priorityCell = cells[5];
    const priorityContainer = priorityCell.querySelector('div');
    if (priorityContainer) {
      const priorityDot = priorityContainer.querySelector('div');
      const priorityText = priorityContainer.querySelector('span');
      const priorityColor = this.getPriorityColor(capa.priority);
      if (priorityDot) priorityDot.className = `w-3 h-3 rounded-full ${priorityColor}`;
      if (priorityText) priorityText.textContent = capa.priority ? capa.priority.charAt(0).toUpperCase() + capa.priority.slice(1) : '-';
    }

    // Cell 6: Due Date
    const dueDateCell = cells[6];
    const dueDateSpan = dueDateCell.querySelector('span');
    if (dueDateSpan) dueDateSpan.textContent = capa.due_date ? this.formatDate(capa.due_date) : '-';

    // Cell 7: Status
    const statusCell = cells[7];
    const statusSpan = statusCell.querySelector('span');
    if (statusSpan) {
      const statusStyle = this.getStatusStyle(capa.status, capa.due_date);
      statusSpan.className = `text-xs px-4 py-1 rounded-full font-medium ${statusStyle.bg} ${statusStyle.text}`;
      statusSpan.textContent = statusStyle.label;
    }

    // Cell 8: Actions menu (update edit button data attributes and archive/unarchive button)
    const actionsCell = cells[8];
    const editButton = actionsCell.querySelector('button[onclick*="openEditCapaModal"]');
    if (editButton) {
      editButton.dataset.capaTitle = capa.title || '';
      editButton.dataset.capaDescription = capa.description || '';
      editButton.dataset.capaSource = capa.source || '';
      editButton.dataset.capaStandardId = capa.standard_id || '';
      editButton.dataset.capaPriority = capa.priority || '';
      editButton.dataset.capaDueDate = capa.due_date || '';
      editButton.dataset.capaStatus = capa.status || '';
      editButton.dataset.capaAssigneeIds = capa.assignee_ids || '';
    }

    // Fix Archive/Unarchive button for archives view
    if (isArchives) {
      const archiveButton = actionsCell.querySelector('button[onclick*="archiveCapa"], button[onclick*="unarchiveCapa"]');
      if (archiveButton) {
        archiveButton.textContent = 'Unarchive';
        archiveButton.setAttribute('onclick', `unarchiveCapa('${capa.id}')`);
      }
    }
  }
}


