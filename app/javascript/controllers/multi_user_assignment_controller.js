import { Controller } from "@hotwired/stimulus"
import Choices from "choices.js"

// ─── Module-level singleton click handler ────────────────────────────────────
let instanceCount = 0

function handleGlobalOpenClick(e) {
  const button = e.target.closest('.open-multi-assign-btn')
  if (!button) return
  e.preventDefault()

  const modalId = button.dataset.modalId
  const modal = document.getElementById(modalId)
  if (!modal) {
    console.error('Modal not found:', modalId)
    return
  }

  // Walk up to the Stimulus controller element wrapping this modal
  const controllerEl = modal.closest('[data-controller~="multi-user-assignment"]')
  if (!controllerEl) {
    console.error('multi-user-assignment controller element not found for modal:', modalId)
    return
  }

  const controller = window.Stimulus?.getControllerForElementAndIdentifier(
    controllerEl,
    'multi-user-assignment'
  )
  if (!controller) {
    console.error('Stimulus controller instance not found')
    return
  }

  controller.openFromButton(button)
}
// ─────────────────────────────────────────────────────────────────────────────

export default class extends Controller {
  static targets = [
    "modal",
    "form",
    "title",
    "contributorsSelect",
    "contributorsList",
    "toolClauseId",
    "checklistItemId",
    "usersToRemove",
    "currentAssignmentsSection",
    "currentAssignmentsList"
  ]

  static values = {
    modal: String
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  connect() {
    this.selectedContributors = []
    this.contributorChoices = null
    this.initialContributorChoices = []
    this.currentAssignedUsers = []
    this.isSyncing = false

    // Register the global click handler only once across all instances
    if (instanceCount === 0) {
      document.addEventListener('click', handleGlobalOpenClick)
    }
    instanceCount++
  }

  disconnect() {
    instanceCount--
    if (instanceCount === 0) {
      document.removeEventListener('click', handleGlobalOpenClick)
    }
    this._destroyChoices()
  }

  _destroyChoices() {
    if (this.contributorChoices) {
      this.contributorChoices.destroy()
      this.contributorChoices = null
    }
  }

  // ── Open ────────────────────────────────────────────────────────────────────

  openFromButton(button) {
    const toolClauseId = button.dataset.toolClauseId
    const checklistItemId = button.dataset.checklistItemId
    const checkpointName = button.dataset.checkpointName

    // 1. Set hidden form fields
    if (this.hasToolClauseIdTarget) this.toolClauseIdTarget.value = toolClauseId
    if (this.hasChecklistItemIdTarget) this.checklistItemIdTarget.value = checklistItemId

    // Update title
    if (this.hasTitleTarget) {
      this.titleTarget.textContent = `Assign Contributors — ${checkpointName}`
    }

    // 2. Reset state
    this._resetState()

    // 3. Show modal FIRST so the dialog has real dimensions
    this.modalTarget.showModal()

    // 4. Now initialise Choices (modal is visible)
    this.initializeSelects()

    // 5. Fetch existing assignments in background
    this._loadAndDisplayAssignments(toolClauseId, checklistItemId)
  }

  // ── Choices.js ──────────────────────────────────────────────────────────────

  initializeSelects() {
    this._destroyChoices()

    const commonConfig = {
      allowHTML: false,
      searchEnabled: true,
      shouldSort: false,
      itemSelectText: '',
      callbackOnCreateTemplates: (template) => {
        const createItemHTML = (data, isChoice = false) => {
          const props = data.customProperties || {}
          if (Object.keys(props).length === 0 && data.element) {
            Object.assign(props, data.element.dataset)
          }

          const profileImageUrl = props.profileImageUrl || props.profile_image_url

          const avatarHtml = profileImageUrl
            ? `<img src="${profileImageUrl}" class="w-6 h-6 rounded-full object-cover flex-shrink-0">`
            : `<div class="w-6 h-6 rounded-full bg-purple-200 flex items-center justify-center text-[10px] text-purple-700 font-bold flex-shrink-0">${data.label.charAt(0).toUpperCase()}</div>`

          const dataAttrs = isChoice
            ? `data-choice ${data.disabled ? 'data-choice-disabled aria-disabled="true"' : 'data-choice-selectable'}`
            : `data-item ${data.active ? 'aria-selected="true"' : ''} ${data.disabled ? 'aria-disabled="true"' : ''}`;

          return template(`
            <div class="choices__item ${isChoice ? 'choices__item--choice' : ''} ${data.highlighted ? 'is-highlighted' : ''} ${data.placeholder ? 'choices__item--placeholder' : 'choices__item--selectable'}" 
                 ${dataAttrs} 
                 data-id="${data.id}" 
                 data-value="${data.value}" 
                 ${isChoice ? 'role="option"' : ''}>
              <div class="flex items-center gap-3">
                 ${avatarHtml}
                 <div class="flex flex-col">
                   <span class="text-sm font-medium text-[#0D1120]">${data.label}</span>
                   <span class="text-xs text-[#797C81]">${props.role || ''}</span>
                 </div>
              </div>
            </div>
          `)
        }

        return {
          choice: (classNames, data) => createItemHTML(data, true),
          item: (classNames, data) => createItemHTML(data, false)
        }
      }
    }

    if (this.hasContributorsSelectTarget) {
      // Store initial choices for syncing later
      this.initialContributorChoices = Array.from(this.contributorsSelectTarget.options).map(opt => {
        let customProps = { ...opt.dataset }
        if (opt.dataset.customProperties) {
          try {
            customProps = JSON.parse(opt.dataset.customProperties)
          } catch (e) {
            console.error('Error parsing custom properties', e)
          }
        }
        return {
          value: opt.value,
          label: opt.text,
          selected: opt.selected,
          disabled: opt.disabled,
          customProperties: customProps
        }
      })

      this.contributorChoices = new Choices(this.contributorsSelectTarget, {
        ...commonConfig,
        placeholder: true,
        placeholderValue: "Select contributors",
        removeItemButton: true,
      })

      // Choices.js 10 does not auto-parse data-custom-properties from DOM options,
      // so the first render shows initials-only fallback. Replace the choices with
      // our pre-parsed array so customProperties (including profile_image_url)
      // are present from the start.
      this.contributorChoices.setChoices(this.initialContributorChoices, 'value', 'label', true)
    }

  }

  onSelectChange() {
    if (this.isSyncing) return

    this.isSyncing = true
    try {
      this.updateContributorsList()
    } finally {
      this.isSyncing = false
    }
  }

  syncContributorOptions() {
    if (!this.contributorChoices) return

    const existingUserIds = (this.currentAssignedUsers || []).map(u => String(u.id))

    // Simply filter out users who are already assigned to the subcheckpoint
    const updatedChoices = this.initialContributorChoices.filter(choice => {
      if (!choice.value) return true
      return !existingUserIds.includes(String(choice.value))
    })

    this.contributorChoices.setChoices(updatedChoices, 'value', 'label', true)
  }

  // ── Currently-assigned users list ───────────────────────────────────────────

  async _loadAndDisplayAssignments(toolClauseId, checklistItemId) {
    try {
      const response = await fetch(
        `/tools/get_assignments?tool_clause_id=${toolClauseId}&checklist_item_id=${checklistItemId}`,
        {
          headers: {
            'Accept': 'application/json',
            'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content
          }
        }
      )

      if (!response.ok) return

      const data = await response.json()

      // Build flat list of currently assigned contributors only
      const allUsers = (data.contributors || []).map(c => ({
        ...c,
        role: 'Contributor',
        customProperties: { role: c.company_role || 'Contributor', profile_image_url: c.profile_image_url }
      }))

      this.isSyncing = true
      try {
        this.currentAssignedUsers = allUsers
        this._renderCurrentAssignments(allUsers)

        // Update dropdown to hide already assigned users
        this.syncContributorOptions()

        // Reset the "Add" selections
        if (this.contributorChoices) this.contributorChoices.removeActiveItems()
      } finally {
        this.isSyncing = false
      }

    } catch (err) {
      console.error('Error loading existing assignments:', err)
    }
  }

  _renderCurrentAssignments(users) {
    if (!this.hasCurrentAssignmentsSectionTarget || !this.hasCurrentAssignmentsListTarget) return

    // Reset users-to-remove field
    if (this.hasUsersToRemoveTarget) this.usersToRemoveTarget.value = ''

    if (users.length === 0) {
      this.currentAssignmentsSectionTarget.style.display = 'none'
      return
    }

    this.currentAssignmentsSectionTarget.style.display = 'block'

    const html = users.map(user => {
      const roleColor = user.role === 'Auditor' ? 'bg-blue-100 text-blue-700' : 'bg-purple-100 text-purple-700'
      const canRemove = user.status !== 'approved' && user.status !== 'auditor_approved'
      const initials = user.name.split(' ').filter(n => n.length > 0).map(n => n[0]).join('').toUpperCase().substring(0, 2)
      const profileImageUrl = user.profile_image_url || user.profileImageUrl
      const avatarHtml = profileImageUrl
        ? `<img src="${this.escapeHtml(profileImageUrl)}" alt="${this.escapeHtml(user.name)}" class="w-full h-full object-cover">`
        : `<div class="w-full h-full bg-purple-200 flex items-center justify-center text-xs font-bold text-purple-700">${this.escapeHtml(initials)}</div>`

      const actionHtml = canRemove
        ? `<button type="button"
                   class="remove-assigned-user-btn text-red-600 hover:text-red-800 p-1"
                   data-action="click->multi-user-assignment#removeAssignedUser"
                   data-user-id="${user.id}"
                   title="Remove user">
             <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
               <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
             </svg>
           </button>`
        : `<span class="text-xs text-gray-500 px-2 py-1 bg-gray-200 rounded">Cannot remove (approved)</span>`

      return `
        <div class="user-assignment-row flex items-center justify-between p-3 border border-gray-200 rounded-lg bg-gray-50" data-user-id="${user.id}">
          <div class="flex items-center gap-3">
            <div class="w-8 h-8 rounded-full bg-purple-200 flex items-center justify-center overflow-hidden">
              ${avatarHtml}
            </div>
            <div>
              <div class="text-sm font-medium text-gray-900">${this.escapeHtml(user.name)}</div>
              <div class="text-xs text-gray-500">${this.escapeHtml(user.company_role || 'User')}</div>
            </div>
            <span class="px-2 py-1 ${roleColor} rounded-full text-xs font-medium">${user.role}</span>
          </div>
          ${actionHtml}
        </div>`
    }).join('')

    this.currentAssignmentsListTarget.innerHTML = html
  }

  removeAssignedUser(event) {
    const btn = event.target.closest('.remove-assigned-user-btn')
    if (!btn) return
    event.preventDefault()
    event.stopPropagation()

    const userId = btn.dataset.userId
    const userRow = btn.closest('.user-assignment-row')
    if (!userRow) return

    // Track for server-side removal (saved assignments)
    if (this.hasUsersToRemoveTarget) {
      const existing = this.usersToRemoveTarget.value
        ? this.usersToRemoveTarget.value.split(',')
        : []
      if (!existing.includes(String(userId))) {
        existing.push(String(userId))
        this.usersToRemoveTarget.value = existing.join(',')
      }
    }

    userRow.remove()

    // Update state and refresh dropdown so user appears back in options
    this.currentAssignedUsers = this.currentAssignedUsers.filter(u => String(u.id) !== String(userId))
    this.syncContributorOptions()

    // Hide section if empty
    if (this.hasCurrentAssignmentsListTarget &&
      this.currentAssignmentsListTarget.children.length === 0 &&
      this.hasCurrentAssignmentsSectionTarget) {
      this.currentAssignmentsSectionTarget.style.display = 'none'
    }
  }

  // ── Contributors list (displayed below the select) ───────────────────────────

  updateContributorsList() {
    if (!this.hasContributorsListTarget || !this.contributorChoices) return

    const selectedItems = this.contributorChoices.getValue()

    let html = ''
    selectedItems.forEach((item) => {
      const userId = item.value
      const userName = item.label
      const props = item.customProperties || {}
      if (Object.keys(props).length === 0 && item.element) {
        Object.assign(props, item.element.dataset)
      }
      const userRole = props.role || 'User'
      const parts = userName.split(' ').filter(n => n.length > 0)
      const initials = parts.length >= 2
        ? (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
        : (parts[0] ? parts[0][0].toUpperCase() : 'U')
      const profileImageUrl = props.profileImageUrl || props.profile_image_url
      const avatarHtml = profileImageUrl
        ? `<img src="${this.escapeHtml(profileImageUrl)}" alt="${this.escapeHtml(userName)}" class="w-full h-full object-cover">`
        : `<div class="w-full h-full bg-purple-200 flex items-center justify-center text-xs font-bold text-purple-700">${this.escapeHtml(initials)}</div>`

      html += `
        <div class="flex items-center justify-between p-3 bg-purple-50 border border-purple-200 rounded-lg">
          <div class="flex items-center gap-3">
            <div class="w-8 h-8 rounded-full bg-purple-200 flex items-center justify-center overflow-hidden">
              ${avatarHtml}
            </div>
            <div>
              <div class="text-sm font-medium text-gray-900">${this.escapeHtml(userName)}</div>
              <div class="text-xs text-gray-500">${this.escapeHtml(userRole)}</div>
            </div>
          </div>
          <button type="button"
                  class="text-red-600 hover:text-red-800"
                  data-action="click->multi-user-assignment#removeContributor"
                  data-user-id="${userId}">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
            </svg>
          </button>
        </div>`
    })

    this.contributorsListTarget.innerHTML =
      html || '<p class="text-sm text-gray-500 text-center py-4">No contributors selected</p>'
  }

  removeContributor(event) {
    event.preventDefault()
    event.stopPropagation()
    const userId = event.currentTarget.dataset.userId

    if (this.contributorChoices) {
      // This will trigger the Stimulus 'change' action, but we trigger it manually
      // to be 100% sure the UI refresh happens immediately.
      this.contributorChoices.removeActiveItemsByValue(String(userId))
      this.onSelectChange()
    }
  }

  // ── Close / Reset ────────────────────────────────────────────────────────────

  close() {
    this.modalTarget.close()
    this._resetState()
  }

  _resetState() {
    if (this.hasFormTarget) this.formTarget.reset()
    if (this.hasUsersToRemoveTarget) this.usersToRemoveTarget.value = ''

    if (this.contributorChoices) this.contributorChoices.removeActiveItems()

    this.selectedContributors = []
    this.updateContributorsList()

    if (this.hasCurrentAssignmentsSectionTarget) {
      this.currentAssignmentsSectionTarget.style.display = 'none'
    }
    if (this.hasCurrentAssignmentsListTarget) {
      this.currentAssignmentsListTarget.innerHTML = ''
    }
  }

  // ── Submit ───────────────────────────────────────────────────────────────────

  async submit(event) {
    event.preventDefault()

    const formData = new FormData(this.formTarget)

    try {
      const response = await fetch(this.formTarget.action, {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content,
          'Accept': 'application/json'
        }
      })

      if (response.ok) {
        const data = await response.json()

        this.close()

        if (data.notification_html) {
          document.dispatchEvent(new CustomEvent('toast:show', {
            detail: { notificationHtml: data.notification_html },
            bubbles: true
          }))
        } else {
          this.showNotification(data.message || 'Users assigned successfully', 'success')
        }

      } else {
        const data = await response.json()
        this.showNotification(data.error || 'Failed to assign users', 'error')
      }
    } catch (error) {
      console.error('Error submitting assignment:', error)
      this.showNotification('An error occurred while assigning users', 'error')
    }
  }

  // ── Utilities ─────────────────────────────────────────────────────────────────

  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text ?? ''
    return div.innerHTML
  }

  showNotification(message, type = 'success') {
    const toast = document.createElement('div')
    toast.className = `fixed top-4 right-4 z-[1000] px-6 py-3 rounded-lg shadow-lg text-white font-medium transition-all duration-300 ${type === 'success' ? 'bg-green-600' : 'bg-red-600'
      }`
    toast.textContent = message
    document.body.appendChild(toast)
    setTimeout(() => { toast.style.opacity = '1' }, 10)
    setTimeout(() => {
      toast.style.opacity = '0'
      setTimeout(() => toast.remove(), 300)
    }, 3000)
  }
}
