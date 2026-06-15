import { Controller } from "@hotwired/stimulus";
import Choices from "choices.js";

// Controls the CAPA Action modal: create/edit actions and manage assignees
export default class extends Controller {
  static targets = [
    "assignedUsers", "userSelect",
    "form", "actionId", "title", "actionType", "status", "dueDate", "notes",
    "modalTitle", "modalSubtitle", "submitButton"
  ];
  static values = { deleteIconPath: String, capaId: String };

  connect() {
    this.choices = null;

    this.translations = {
      createTitle: this.element.dataset.createTitle || 'Assign Action',
      createSubtitle: this.element.dataset.createSubtitle || 'Create a new corrective or preventive action.',
      createSubmit: this.element.dataset.createSubmit || 'Create Action',
      createLoading: this.element.dataset.createLoading || 'Creating...',
      editTitle: this.element.dataset.editTitle || 'Edit Action',
      editSubtitle: this.element.dataset.editSubtitle || 'Update action details.',
      editSubmit: this.element.dataset.editSubmit || 'Save Changes',
      editLoading: this.element.dataset.editLoading || 'Saving...',
      deleteConfirm: this.element.dataset.deleteConfirm || 'Are you sure you want to delete this action?',
      deleteLoading: this.element.dataset.deleteLoading || 'Deleting...',
      deleteError: this.element.dataset.deleteError || 'Failed to delete action',
      deleteButton: this.element.dataset.deleteButton || 'Delete',
      networkError: this.element.dataset.networkError || 'Network error. Please try again.',
      generateLoading: this.element.dataset.generateLoading || 'Generating...',
      generateError: this.element.dataset.generateError || 'Failed to generate actions'
    };

    const modal = document.getElementById('capaActionModal');
    if (modal) {
      this.modalObserver = new MutationObserver((mutations) => {
        mutations.forEach((mutation) => {
          if (mutation.type === 'attributes' && mutation.attributeName === 'open') {
            if (modal.hasAttribute('open')) {
              this.initChoices();
            } else {
              console.log('modal closed');
              this.destroyChoices();
            }
          }
        });
      });
      this.modalObserver.observe(modal, { attributes: true });
    }
  }

  disconnect() {
    if (this.modalObserver) {
      this.modalObserver.disconnect();
    }
    this.destroyChoices();
  }

  initChoices() {
    if (this.choices || !this.hasUserSelectTarget) {
      return;
    }

    // Cache original option data BEFORE Choices mutates the DOM
    this._cachedOptionProps = {};
    Array.from(this.userSelectTarget.options).forEach(option => {
      if (option.value && option.dataset.customProperties) {
        this._cachedOptionProps[option.value] = option.dataset.customProperties;
      }
    });

    console.log(this.userSelectTarget.children[0]);

    try {
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
            item: (classNames, data) => {
              return template(`<div style="display: none;" data-item data-id="${data.id}" data-value="${data.value}"></div>`);
            },
            choice: (classNames, data) => {
              console.log('data', data);

              const props = this.getChoiceProps(data);

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

    // Listen for changes
    this.userSelectTarget.addEventListener('change', () => this.updateChipList());
    this.userSelectTarget.addEventListener('addItem', () => this.updateChipList());
    this.userSelectTarget.addEventListener('removeItem', () => this.updateChipList());
  }

  destroyChoices() {
    if (this.choices) {
      this.choices.destroy();
      this.choices = null;

      // Re-apply cached data-custom-properties after Choices strips them on destroy
      if (this._cachedOptionProps && this.hasUserSelectTarget) {
        Array.from(this.userSelectTarget.options).forEach(option => {
          if (this._cachedOptionProps[option.value]) {
            option.dataset.customProperties = this._cachedOptionProps[option.value];
          }
        });
      }
    }
  }

  getChoiceProps(item) {
    // 1. Try existing customProperties on the item
    if (item.customProperties && Object.keys(item.customProperties).length > 0) {
      return item.customProperties;
    }

    let element = item.element;

    // 2. Retry finding the element if it's missing but we have a value.
    if (!element && this.hasUserSelectTarget && item.value !== undefined && item.value !== null) {
      const options = this.userSelectTarget.options;
      for (let i = 0; i < options.length; i++) {
        // Use loose equality to match string/number
        if (options[i].value == item.value) {
          element = options[i];
          break;
        }
      }
    }

    if (element) {
      if (element.dataset.customProperties) {
        try {
          return JSON.parse(element.dataset.customProperties);
        } catch (e) {
          // Fallback
        }
      }
      // As a last fallback, return dataset directly
      return Object.assign({}, element.dataset);
    }

    return {};
  }

  updateChipList() {
    if (!this.hasAssignedUsersTarget) return;

    const selectedItems = this.choices.getValue();
    this.assignedUsersTarget.innerHTML = '';

    if (selectedItems.length === 0) return;

    selectedItems.forEach(item => {
      const props = this.getChoiceProps(item);

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

      // Fallback for delete icon path
      const modal = document.getElementById("capaActionModal");
      const deleteIconPath = modal?.dataset.capasCapaActionDeleteIconPathValue || this.deleteIconPathValue || (window.assetPaths && window.assetPaths.deleteIcon) || "";

      chip.innerHTML = `
        <div class="flex items-center gap-2 min-w-0 flex-1">
          ${avatarHtml}
          <span class="text-sm text-[#0D1120] truncate font-medium">${this.escapeHtml(name)}</span>
          <span class="text-xs text-[#797C81] flex-shrink-0 bg-white px-2 py-0.5 rounded-full border border-[#E3E3E3]">${this.escapeHtml(role)}</span>
        </div>
        <button type="button" class="text-[#797C81] hover:text-[#EA4034] transition-colors flex-shrink-0 p-1" data-action="click->capas--capa-action#removeUser" data-value="${item.value}">
           <img src="${deleteIconPath}" class="w-4 h-4" alt="Remove name" />
        </button>
      `;
      this.assignedUsersTarget.appendChild(chip);
    });
  }

  openCreateModal() {
    const modal = document.getElementById('capaActionModal');
    if (!modal) return;

    this.resetFormState();

    const form = modal.querySelector('[data-capas--capa-action-target="form"]');
    const actionId = modal.querySelector('[data-capas--capa-action-target="actionId"]');
    const modalTitle = modal.querySelector('[data-capas--capa-action-target="modalTitle"]');
    const modalSubtitle = modal.querySelector('[data-capas--capa-action-target="modalSubtitle"]');
    const submitButton = modal.querySelector('[data-capas--capa-action-target="submitButton"]');

    if (!form || !actionId || !modalTitle || !modalSubtitle || !submitButton) return;

    form.reset();
    actionId.value = '';
    modalTitle.textContent = this.translations.createTitle;
    modalSubtitle.textContent = this.translations.createSubtitle;
    submitButton.textContent = this.translations.createSubmit;

    modal.showModal();
    this.initChoices();
  }

  openEditModal(event) {
    const el = event.currentTarget;
    const modal = document.getElementById('capaActionModal');
    if (!modal) return;

    // Close any open dropdown
    if (el && typeof el.closest === 'function') {
      const dropdown = el.closest('[data-controller*="dropdown"]');
      if (dropdown) {
        if (dropdown.tagName === 'DETAILS') {
          dropdown.open = false;
        } else {
          dropdown.querySelector('[data-dropdown-target="menu"]')?.classList.add('hidden');
        }
      }
    }

    this.resetFormState();

    const form = modal.querySelector('[data-capas--capa-action-target="form"]');
    const assignedUsers = modal.querySelector('[data-capas--capa-action-target="assignedUsers"]');
    const actionId = modal.querySelector('[data-capas--capa-action-target="actionId"]');
    const title = modal.querySelector('[data-capas--capa-action-target="title"]');
    const actionType = modal.querySelector('[data-capas--capa-action-target="actionType"]');
    const status = modal.querySelector('[data-capas--capa-action-target="status"]');
    const dueDate = modal.querySelector('[data-capas--capa-action-target="dueDate"]');
    const notes = modal.querySelector('[data-capas--capa-action-target="notes"]');
    const modalTitle = modal.querySelector('[data-capas--capa-action-target="modalTitle"]');
    const modalSubtitle = modal.querySelector('[data-capas--capa-action-target="modalSubtitle"]');
    const submitButton = modal.querySelector('[data-capas--capa-action-target="submitButton"]');

    if (!form || !actionId) return;

    actionId.value = el.dataset.actionId || '';
    if (title) title.value = el.dataset.actionTitle || '';
    if (actionType) actionType.value = el.dataset.actionType || 'corrective';
    if (status) status.value = el.dataset.actionStatus || 'started';
    if (dueDate) dueDate.value = el.dataset.actionDueDate || '';
    if (notes) notes.value = el.dataset.actionNotes || '';

    if (modalTitle) modalTitle.textContent = this.translations.editTitle;
    if (modalSubtitle) modalSubtitle.textContent = this.translations.editSubtitle;
    if (submitButton) submitButton.textContent = this.translations.editSubmit;

    modal.showModal();
    this.initChoices();

    // Set assigned users in Choices
    if (this.choices) {
      const idsRaw = el.dataset.actionAssigneeIds || '';
      const assignedUserIds = idsRaw.split(',').map(s => s.trim()).filter(Boolean);

      if (assignedUserIds.length > 0) {
        this.choices.setChoiceByValue(assignedUserIds);
      }

      // Force update chips immediately
      this.updateChipList();
    }
  }

  closeModal() {
    const modal = document.getElementById('capaActionModal');
    if (modal) {
      this.resetFormState();
      modal.close();
    }
  }

  resetFormState() {
    if (this.choices) {
      this.choices.removeActiveItems();
    }
    if (this.hasAssignedUsersTarget) {
      this.assignedUsersTarget.innerHTML = "";
    }
  }

  // Deprecated manual add, choices handles this but we keep method to prevent errors if button exists
  addUser(event) {
    if (event) event.preventDefault();
  }

  removeUser(event) {
    const button = event.currentTarget;
    const value = button.dataset.value;
    if (value) {
      this.choices.removeActiveItemsByValue(value);
    }
  }

  // helpers for createUserChip no longer needed but `escapeHtml` is used elsewhere?
  // `createUserChip` is used by updateChipList but we inlined the HTML there.
  // We should keep `escapeHtml` as it's likely used by updateChipList and others.

  // NOTE: submitForm follows after...

  // ─── Form submit ─────────────────────────────────────────────────────────────

  async submitForm(event) {
    event.preventDefault()
    const form = event.target
    const modal = document.getElementById('capaActionModal')
    if (!modal) return

    const actionId = modal.querySelector('[data-capas--capa-action-target="actionId"]')?.value || ''
    const submitButton = modal.querySelector('[data-capas--capa-action-target="submitButton"]')
    const capaId = form.querySelector('input[name="capa_id"]').value
    const formData = new FormData(form)

    // Always send company_user_ids, even empty (to allow clearing all assignments)
    if (!formData.has('capa_action[company_user_ids][]')) {
      formData.append('capa_action[company_user_ids][]', '')
    }

    const isEdit = !!actionId
    const url = isEdit
      ? `/dashboard/capa_management/${capaId}/capa_actions/${actionId}`
      : `/dashboard/capa_management/${capaId}/capa_actions`
    const method = isEdit ? 'PATCH' : 'POST'

    try {
      if (submitButton) {
        submitButton.disabled = true
        submitButton.textContent = isEdit ? this.translations.editLoading : this.translations.createLoading
      }

      const response = await fetch(url, {
        method,
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Accept': 'application/json'
        },
        body: formData
      })

      if (!response.ok) {
        const err = await response.json().catch(() => ({}))
        err.notification_html
          ? this.dispatchToast(err.notification_html)
          : this.dispatchToast(err.error || `Failed to ${isEdit ? 'update' : 'create'} action`, 'error')
        return
      }

      const result = await response.json()
      if (result.notification_html) this.dispatchToast(result.notification_html)
      this.closeModal()
      this.updateUIAfterAction(result, capaId, actionId, isEdit)
    } catch (error) {
      console.error('Form submission error:', error)
      this.dispatchToast(this.translations.networkError, 'error')
    } finally {
      if (submitButton) {
        submitButton.disabled = false
        submitButton.textContent = isEdit ? this.translations.editSubmit : this.translations.createSubmit
      }
    }
  }

  // ─── Delete ──────────────────────────────────────────────────────────────────

  async deleteAction(event) {
    const button = event.currentTarget
    const actionId = button.dataset.actionId
    const capaId = button.dataset.capaId

    // Close dropdown
    const dropdown = button.closest('[data-controller*="dropdown"]')
    if (dropdown) dropdown.querySelector('[data-dropdown-target="menu"]')?.classList.add('hidden')

    const confirmed = window.customConfirm
      ? await window.customConfirm(this.translations.deleteConfirm)
      : confirm(this.translations.deleteConfirm)

    if (!confirmed) return

    try {
      button.disabled = true
      button.textContent = this.translations.deleteLoading

      const response = await fetch(`/dashboard/capa_management/${capaId}/capa_actions/${actionId}`, {
        method: 'DELETE',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Accept': 'application/json'
        }
      })

      if (!response.ok) {
        const err = await response.json().catch(() => ({}))
        err.notification_html
          ? this.dispatchToast(err.notification_html)
          : this.dispatchToast(err.error || this.translations.deleteError, 'error')
        return
      }

      const result = await response.json()
      if (result.notification_html) this.dispatchToast(result.notification_html)
      this.updateUIAfterActionDelete(actionId, capaId, result)
    } catch (error) {
      console.error('Delete error:', error)
      this.dispatchToast(this.translations.networkError, 'error')
    } finally {
      button.disabled = false
      button.textContent = this.translations.deleteButton
    }
  }

  // ─── UI helpers ──────────────────────────────────────────────────────────────

  createUserChip(userId, userName, userRole, profileImageUrl = '') {
    const chip = document.createElement('div')
    chip.className = 'flex items-center gap-3 h-12 px-3 border border-[#E3E3E3] rounded-xl user-chip'
    chip.dataset.userId = userId
    // Store these so _restoreOptionToDatalist can read them after the chip is
    // still in the DOM at removal time.
    chip.dataset.userName = userName || ''
    chip.dataset.userRole = userRole || ''
    chip.dataset.profileImageUrl = profileImageUrl || ''

    const deleteIconPath = this.deleteIconPathValue || '/assets/delete-clause-icon.svg'
    const userInitial = userName ? userName.charAt(0).toUpperCase() : ''
    const escapedName = this.escapeHtml(userName || '')
    const escapedRole = this.escapeHtml(userRole || '')

    const avatarHtml = profileImageUrl
      ? `<img src="${this.escapeHtml(profileImageUrl)}" alt="${escapedName}" class="w-6 h-6 rounded-full object-cover flex-shrink-0">`
      : `<div class="w-6 h-6 rounded-full bg-[#E3E3E3] flex items-center justify-center text-xs text-[#0D1120] font-medium flex-shrink-0" title="${escapedName}">${userInitial}</div>`

    chip.innerHTML = `
      ${avatarHtml}
      <span class="text-sm font-medium flex-1">${escapedName}</span>
      <span class="text-xs text-[#576A83] bg-[#F7F7FD] px-3 py-1 rounded-full">${escapedRole}</span>
      <button type="button" class="p-1" data-action="click->capas--capa-action#removeUser">
        <img src="${deleteIconPath}" class="w-4 h-4" alt="Remove user" />
      </button>
    `
    return chip
  }

  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }

  dispatchToast(notificationHtmlOrMessage, type = 'success') {
    let notificationHtml = notificationHtmlOrMessage

    if (!notificationHtmlOrMessage || (typeof notificationHtmlOrMessage === 'string' && !notificationHtmlOrMessage.includes('data-toast-target'))) {
      const bgColor = type === 'success'
        ? 'bg-[#FFFFFF] border-[#E3E3E3] border-l-4 border-l-[#5C3984]'
        : 'bg-[#FFFFFF] border-[#E3E3E3] border-l-4 border-l-red-500'
      const icon = type === 'success'
        ? '<svg class="w-5 h-5 text-[#5C3984]" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/></svg>'
        : '<svg class="w-5 h-5 text-red-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/></svg>'

      notificationHtml = `
        <div data-toast-target="notification"
             class="${bgColor} rounded-lg shadow-lg p-4 flex items-start gap-3 transform opacity-0 translate-x-full transition ease-out duration-300">
          ${icon}
          <div class="flex-1 text-sm text-[#0D1120] font-medium">${notificationHtmlOrMessage || 'Operation completed'}</div>
          <button data-action="click->toast#close" class="text-gray-400 hover:text-gray-600 transition-colors">
            <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"/>
            </svg>
          </button>
        </div>
      `
    }

    document.dispatchEvent(new CustomEvent('toast:show', { detail: { notificationHtml }, bubbles: true }))
  }

  detectPageContext() {
    return window.location.pathname.match(/\/capa_management\/[a-f0-9-]+$/i) ? 'show' : 'other'
  }

  updateUIAfterAction(result, capaId, actionId, isEdit) {
    if (this.detectPageContext() !== 'show' || !result.action_html) return

    const actionsSection = document.querySelector('[data-controller*="capas--capa-action"]')
    let actionsTable = actionsSection ? actionsSection.querySelector('table tbody') : null

    if (!actionsTable && !isEdit) {
      const emptyState = actionsSection
        ? Array.from(actionsSection.querySelectorAll('.border')).find(el => el.textContent.includes('No actions have been assigned'))
        : null

      if (emptyState) {
        const tableHtml = `
          <div class="border border-[#E3E3E3] rounded-xl overflow-hidden">
            <table class="w-full">
              <thead class="bg-[#F7F7FD] border-b border-[#E3E3E3]">
                <tr>
                  <th class="text-left p-4"><span class="text-xs font-semibold text-[#797C81]">Title</span></th>
                  <th class="text-left p-4"><span class="text-xs font-semibold text-[#797C81]">Action Type</span></th>
                  <th class="text-left p-4"><span class="text-xs font-semibold text-[#797C81]">Assignees</span></th>
                  <th class="text-left p-4"><span class="text-xs font-semibold text-[#797C81]">Status</span></th>
                  <th class="text-left p-4"><span class="text-xs font-semibold text-[#797C81]">Due Date</span></th>
                  <th class="text-left p-4"><span class="text-xs font-semibold text-[#797C81]">Notes</span></th>
                  <th class="text-right p-4"></th>
                </tr>
              </thead>
              <tbody class="divide-y divide-[#E3E3E3]"></tbody>
            </table>
          </div>`
        const temp = document.createElement('div')
        temp.innerHTML = tableHtml.trim()
        const tableWrapper = temp.firstElementChild
        if (tableWrapper && emptyState.parentNode) {
          emptyState.replaceWith(tableWrapper)
          actionsTable = tableWrapper.querySelector('tbody')
        }
      }
    }

    if (actionsTable) {
      const temp = document.createElement('tbody')
      temp.innerHTML = result.action_html.trim()
      const newRow = temp.firstElementChild

      if (isEdit && actionId) {
        const existingRow = actionsTable.querySelector(`tr[data-action-id="${actionId}"]`)
        if (existingRow && newRow) existingRow.replaceWith(newRow)
      } else if (newRow) {
        if (result.action?.id) newRow.setAttribute('data-action-id', result.action.id)
        actionsTable.appendChild(newRow)
      }
    }

    if (result.activity_log_html) {
      const content = document.querySelector('[data-activity-tab-target="content"]')
      if (content) content.innerHTML = result.activity_log_html.trim()
    }
  }

  updateUIAfterActionDelete(actionId, capaId, result) {
    if (this.detectPageContext() !== 'show') return

    const actionsSection = document.querySelector('[data-controller*="capas--capa-action"]')
    const actionsTable = actionsSection ? actionsSection.querySelector('table tbody') : null

    if (actionsTable) {
      const rowToRemove = actionsTable.querySelector(`tr[data-action-id="${actionId}"]`)
      if (rowToRemove) {
        rowToRemove.remove()

        if (actionsTable.children.length === 0) {
          const tableWrapper = actionsTable.closest('.border')
          if (tableWrapper) {
            const emptyStateHtml = `
              <div class="border border-[#E3E3E3] rounded-xl p-8 text-center">
                <p class="text-sm text-[#797C81] mb-4">No actions have been assigned yet.</p>
                <button type="button"
                        class="px-4 py-2 bg-[#5C3984] rounded-xl text-sm font-medium text-white hover:opacity-80 flex items-center space-x-2 mx-auto"
                        data-action="click->capas--capa-action#openCreateModal">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"></path>
                  </svg>
                  <span>Assign Action</span>
                </button>
              </div>`
            const temp = document.createElement('div')
            temp.innerHTML = emptyStateHtml.trim()
            const emptyState = temp.firstElementChild
            if (emptyState && tableWrapper.parentNode) tableWrapper.replaceWith(emptyState)
          }
        }
      }
    }

    if (result && result.activity_log_html) {
      const content = document.querySelector('[data-activity-tab-target="content"]')
      if (content) content.innerHTML = result.activity_log_html.trim()
    }
  }

  // ─── Generate actions ────────────────────────────────────────────────────────

  async generateActions(event) {
    const button = event.currentTarget
    const capaId = button.dataset.capaId || this.capaIdValue

    if (!capaId) { console.error('CAPA ID not found'); return }

    if (button.dataset.rootCauseReady !== 'true') {
      alert(button.dataset.rootCauseMessage || 'Complete the questionnaire and root cause before generating actions.')
      return
    }

    const spinner = button.querySelector('[data-generate-actions-spinner]')
    const icon = button.querySelector('[data-generate-actions-icon]')
    const text = button.querySelector('[data-generate-actions-text]')

    button.disabled = true
    spinner?.classList.remove('hidden')
    icon?.classList.add('hidden')
    if (text) text.textContent = this.translations.generateLoading

    try {
      const response = await fetch(`/dashboard/capa_management/${capaId}/generate_actions`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Accept': 'application/json',
          'Content-Type': 'application/json'
        }
      })

      const result = await response.json()
      if (!response.ok) throw new Error(result.error || this.translations.generateError)

      if (result.notification_html) {
        const temp = document.createElement('div')
        temp.innerHTML = result.notification_html.trim()
        const notification = temp.firstElementChild
        const container = document.getElementById('notification-container') || document.body
        if (notification) {
          container.appendChild(notification)
          setTimeout(() => notification.parentNode && notification.remove(), 5000)
        }
      }

      window.location.reload()
    } catch (error) {
      console.error('Error generating actions:', error)
      alert(error.message || this.translations.generateError)
    } finally {
      button.disabled = false
      spinner?.classList.add('hidden')
      icon?.classList.remove('hidden')
      if (text) text.textContent = 'Generate Actions'
    }
  }
}
