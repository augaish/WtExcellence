import { Controller } from "@hotwired/stimulus"
import Choices from "choices.js"

export default class extends Controller {
    static targets = ["dialog", "select", "actionIdInput", "saveButton", "chipList"]

    initialize() {
        this.choices = null
    }

    connect() {
        // Removal of initChoices from connect
        this.choices = null
    }

    disconnect() {
        if (this.choices) {
            this.choices.destroy()
            this.choices = null
        }
    }

    initChoices() {
        if (this.choices) return

        this.choices = new Choices(this.selectTarget, {
            removeItemButton: true,
            searchEnabled: true,
            searchPlaceholderValue: this.selectTarget.dataset.searchPlaceholder,
            placeholder: true,
            placeholderValue: this.selectTarget.dataset.placeholder,
            itemSelectText: '',
            shouldSort: false,
            callbackOnCreateTemplates: function (template) {
                return {
                    choice: (classNames, data) => {
                        const props = data.customProperties || {};
                        // Fallback parsing if customProperties are empty
                        if (Object.keys(props).length === 0 && data.element) {
                            Object.assign(props, data.element.dataset);
                        }
                        const avatarHtml = props.avatar
                            ? `<img src="${props.avatar}" class="w-6 h-6 rounded-full object-cover flex-shrink-0" alt="${props.name}">`
                            : `<div class="w-6 h-6 rounded-full bg-[#E3E3E3] flex items-center justify-center text-[10px] text-[#0D1120] font-bold flex-shrink-0">${props.initial || '?'}</div>`;

                        return template(`
                      <div class="choices__item choices__item--choice ${data.disabled ? 'choices__item--disabled' : 'choices__item--selectable'} ${data.groupId > 0 ? 'choices__item--child' : ''
                            }" data-select-text="${this.config.itemSelectText}" data-choice ${data.disabled
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
        })

        // Listen for changes to update external chip list
        this.selectTarget.addEventListener('change', () => this.updateChipList())
        this.selectTarget.addEventListener('addItem', () => this.updateChipList())
        this.selectTarget.addEventListener('removeItem', () => this.updateChipList())
    }

    updateChipList() {
        if (!this.hasChipListTarget) return

        const selectedItems = this.choices.getValue()
        this.chipListTarget.innerHTML = ''

        if (selectedItems.length === 0) {
            // Optional: show "No assignees yet" placeholder
            return
        }

        selectedItems.forEach(item => {
            const props = item.customProperties || {}
            if (Object.keys(props).length === 0 && item.element) {
                Object.assign(props, item.element.dataset);
            }
            // Retrieve data attributes that might have been put on the option. 
            // Note: choices.js getValue() returns item objects. 
            // If item was created from an option with customProperties, they should be here.

            // Fallback parsing if customProperties is missing but we have label like "Name (Role)"
            let name = props.name || item.label;
            let role = props.role || '';
            let initial = props.initial || (name ? name[0].toUpperCase() : '?');
            let avatar = props.avatar;

            // If no props (e.g. pre-selected values might strictly bind to value), we rely on label parsing if needed.
            // But since we use setChoiceByValue(ids) and the options exist, Choices should re-hydrate props from valid options.

            const chip = document.createElement('div')
            chip.className = 'flex items-center justify-between gap-3 px-3 py-2 rounded-xl bg-[#F7F7FD] border border-[#E3E3E3]'

            const avatarHtml = avatar
                ? `<img src="${avatar}" class="w-7 h-7 rounded-full object-cover flex-shrink-0">`
                : `<div class="w-7 h-7 rounded-full bg-[#D6C4ED] flex items-center justify-center text-xs font-semibold text-[#5C3984] flex-shrink-0">${initial}</div>`;

            chip.innerHTML = `
                <div class="flex items-center gap-2 min-w-0">
                  ${avatarHtml}
                  <span class="text-sm text-[#0D1120] truncate">${name}</span>
                  <span class="text-xs text-[#797C81] flex-shrink-0">(${role || ''})</span>
                </div>
                <button type="button" class="text-[#797C81] hover:text-[#EA4034] transition-colors flex-shrink-0 p-1" data-action="click->capas--assign-assignees#removeChip" data-value="${item.value}">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                  </svg>
                </button>
            `
            this.chipListTarget.appendChild(chip)
        })
    }

    removeChip(event) {
        const value = event.currentTarget.dataset.value
        if (value) {
            this.choices.removeActiveItemsByValue(value)
            // The change listener will trigger updateChipList
        }
    }

    open(event) {
        const { capaId, actionId, assigneeIds } = event.detail
        this.capaId = capaId
        this.actionIdInputTarget.value = actionId

        this.dialogTarget.showModal()
        this.initChoices()

        // Reset selection (safe now that choices is inited)
        this.choices.removeActiveItems()

        if (assigneeIds) {
            // Split by comma and ensure we only pass valid IDs
            const ids = assigneeIds.toString().split(',').filter(id => id && id.trim().length > 0)
            this.choices.setChoiceByValue(ids)
        } else {
            this.updateChipList() // clear chips if empty
        }
        // Ensure UI is synced after modal opens and choices sets values
        setTimeout(() => this.updateChipList(), 50)
    }

    close() {
        this.dialogTarget.close()
    }

    async submit(event) {
        event.preventDefault()

        if (!this.capaId || !this.actionIdInputTarget.value) return

        const btn = this.saveButtonTarget
        const originalText = btn.innerHTML
        btn.disabled = true
        btn.textContent = btn.dataset.savingText

        const selectedValues = this.choices.getValue(true)

        const formData = new FormData()
        formData.append('_method', 'PATCH')

        if (selectedValues.length > 0) {
            selectedValues.forEach(id => formData.append('capa_action[company_user_ids][]', id))
        } else {
            formData.append('capa_action[company_user_ids][]', '')
        }

        try {
            // We need to fetch the CSRF token from the meta tag
            const token = document.querySelector('meta[name="csrf-token"]')?.content

            const response = await fetch(`/dashboard/capa_management/${this.capaId}/capa_actions/${this.actionIdInputTarget.value}`, {
                method: 'POST', // Rails handles PATCH via _method
                headers: {
                    'X-CSRF-Token': token,
                    'Accept': 'application/json'
                },
                body: formData
            })

            const data = await response.json().catch(() => ({}))

            if (data.notification_html) {
                document.dispatchEvent(new CustomEvent('toast:show', {
                    detail: { notificationHtml: data.notification_html }, bubbles: true
                }))
            }

            if (response.ok) {
                this.close()
                window.location.reload()
            }
        } catch (error) {
            console.error('Error submitting form:', error)
        } finally {
            btn.disabled = false
            btn.innerHTML = originalText
        }
    }
}
