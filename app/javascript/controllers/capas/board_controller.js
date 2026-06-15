import { Controller } from "@hotwired/stimulus"

// Handles drag and drop of CAPA cards between columns
export default class extends Controller {
  static targets = ["column", "count"]

  connect() {
    // Listen for manual count updates
    this.boundUpdateCounts = this.updateCounts.bind(this);
    document.addEventListener('capa:counts-update', this.boundUpdateCounts);
  }

  disconnect() {
    document.removeEventListener('capa:counts-update', this.boundUpdateCounts);
  }

  prepareDrag(event) {
    const card = event.currentTarget
    card.classList.add('select-none')
    // Ensure draggable is true (defensive)
    card.setAttribute('draggable', 'true')
  }

  dragStart(event) {
    const card = event.currentTarget
    const capaId = card.dataset.capaId
    const status = card.dataset.capaStatus
    event.dataTransfer.setData("text/plain", JSON.stringify({ id: capaId, status }))
    event.dataTransfer.effectAllowed = "move"
    // Improve cross-browser behavior by ensuring a drag image
    if (event.dataTransfer.setDragImage) {
      event.dataTransfer.setDragImage(card, 10, 10)
    }
  }

  dragEnd(event) {
    const card = event.currentTarget
    card.classList.remove('select-none')
  }

  dragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  async drop(event) {
    event.preventDefault()
    const columnEl = event.currentTarget
    const newStatus = columnEl.dataset.status

    let payload
    try {
      payload = JSON.parse(event.dataTransfer.getData("text/plain"))
    } catch (_) {
      return
    }

    const { id, status: oldStatus } = payload || {}
    if (!id || !newStatus || newStatus === oldStatus) return

    // Find the card in DOM
    const card = this.element.querySelector(`[data-capa-id="${id}"]`)
    if (!card) return

    const clearingAssignments = oldStatus === 'assigned' && newStatus === 'open'
    if (clearingAssignments) {
      const confirmed = await this.confirmAssignedToOpen()
      if (!confirmed) return
    }

    // Get the old column before moving
    const oldColumn = card.closest('[data-capas--board-target="column"]')
    const oldList = oldColumn ? oldColumn.querySelector('[data-role="cards"]') : null

    // Optimistic move - prepend automatically removes from old location
    const newList = columnEl.querySelector('[data-role="cards"]') || columnEl
    newList.prepend(card)
    this.updateCardStatusData(card, newStatus)
    this.updateCardStatusBadge(card, newStatus)
    this.updateCardProgress(card, newStatus)
    
    // Update counts after DOM manipulation
    this.updateCounts()

    try {
      const result = await this.updateStatus(id, newStatus)
      if (clearingAssignments) {
        this.clearCardAssignees(card)
      }
      if (result && result.notification_html) {
        this.dispatchToast(result.notification_html, 'success')
      }
    } catch (e) {
      // Revert on error
      const previousParent = oldList || oldColumn
      if (previousParent) {
        card.remove()
        previousParent.prepend(card)
      }
      this.updateCardStatusData(card, oldStatus)
      this.updateCardStatusBadge(card, oldStatus)
      this.updateCardProgress(card, oldStatus)
      this.updateCounts()
      console.error(e)
      this.dispatchToast("Failed to update status. Please try again.", 'error')
    }
  }

  async updateStatus(id, status) {
    const token = document.querySelector('meta[name="csrf-token"]').getAttribute('content')
    const url = `/dashboard/capa_management/${id}/status`
    const response = await fetch(url, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": token,
        "Accept": "application/json"
      },
      body: JSON.stringify({ status })
    })
    if (!response.ok) {
      const data = await response.json().catch(() => ({}))
      throw new Error(data.error || `HTTP ${response.status}`)
    }
    return await response.json()
  }

  updateCounts() {
    // For each column target, count cards and update the header count
    // Use querySelectorAll as fallback if targets aren't populated
    const columns = (this.columnTargets && this.columnTargets.length > 0) 
      ? this.columnTargets 
      : this.element.querySelectorAll('[data-capas--board-target="column"]');
    
    columns.forEach((col) => {
      const status = col.dataset.status
      // Only count direct children of [data-role="cards"] container to avoid double counting
      const cardsContainer = col.querySelector('[data-role="cards"]')
      if (!cardsContainer) return
      
      // Count only direct children with data-capa-id (not nested elements)
      const cards = Array.from(cardsContainer.children).filter(child => 
        child.hasAttribute('data-capa-id')
      )
      const count = cards.length
      
      // Find corresponding count element within this column
      const countEl = col.querySelector('[data-role="count"]')
      if (countEl) {
        countEl.textContent = String(count).padStart(2, '0')
      }
      const emptyEl = col.querySelector('[data-role="empty"]')
      if (emptyEl) {
        if (count === 0) {
          emptyEl.classList.remove('hidden')
        } else {
          emptyEl.classList.add('hidden')
        }
      }
    })
  }

  updateCardProgress(card, status) {
    // Find the progress section - it contains "Progress:" text
    const progressSections = card.querySelectorAll('.mt-3')
    let progressSection = null
    
    // Find the section that contains "Progress:" text
    for (const section of progressSections) {
      if (section.textContent.includes('Progress:')) {
        progressSection = section
        break
      }
    }
    
    // Only show progress for 'in_progress' status
    if (status === 'in_progress') {
      // Show progress section if it exists
      if (progressSection) {
        progressSection.style.display = ''
        
        // Try to get progress from data attributes if available
        const doneActions = parseInt(card.dataset.doneActions || '0')
        const totalActions = parseInt(card.dataset.totalActions || '0')
        let progressPercent = 0
        
        if (totalActions > 0) {
          progressPercent = Math.round((doneActions / totalActions) * 100)
        }
        
        // Check if CAPA is overdue using data-capa-due-date attribute
        const dueDateStr = card.dataset.capaDueDate
        let isOverdue = false
        if (dueDateStr) {
          const dueDate = new Date(dueDateStr)
          const today = new Date()
          today.setHours(0, 0, 0, 0)
          isOverdue = dueDate < today && status !== 'closed'
        }
        
        // Determine progress bar and text colors based on overdue status
        const progressBarColor = isOverdue ? 'bg-[#EA4034]' : 'bg-[#79BE52]'
        const progressTextColor = isOverdue ? 'text-[#EA4034]' : 'text-[#79BE52]'
        
        // Update progress percentage text (the span after "Progress:")
        const progressTextContainer = progressSection.querySelector('.flex.items-center.justify-between')
        if (progressTextContainer) {
          // Update text color classes
          progressTextContainer.className = `flex items-center justify-between text-xs ${progressTextColor} font-medium`
          const progressText = progressTextContainer.querySelector('span:last-child')
          if (progressText) {
            progressText.textContent = `${progressPercent}%`
          }
        }
        
        // Update progress bar width and color - find the progress bar container (bg-[#E9F0FF])
        const progressBarContainer = progressSection.querySelector('.mt-1')
        if (progressBarContainer) {
          // Find the child div that's the actual progress bar (has style attribute)
          const progressBar = progressBarContainer.querySelector('div[style]')
          if (progressBar) {
            progressBar.style.width = `${progressPercent}%`
            // Update progress bar color classes
            progressBar.className = `h-1.5 ${progressBarColor} rounded-full`
          }
        }
      }
    } else {
      // Hide progress section for non-'in_progress' statuses
      if (progressSection) {
        progressSection.style.display = 'none'
      }
    }
  }

  updateCardStatusBadge(card, status) {
    const styles = {
      open: { label: 'Open', bg: 'bg-[#FEF0FF]', text: 'text-[#B130AC]' },
      assigned: { label: 'Assigned', bg: 'bg-[#E9F5F8]', text: 'text-[#1B94AD]' },
      in_progress: { label: 'In Progress', bg: 'bg-[#E9F0FF]', text: 'text-[#1751A7]' },
      closed: { label: 'Closed', bg: 'bg-[#E0F9DE]', text: 'text-[#3F9011]' }
    }
    
    // Special cases for in_progress status
    let style = styles[status]
    if (status === 'in_progress') {
      const dueDateStr = card.dataset.capaDueDate
      if (dueDateStr) {
        const today = new Date()
        today.setHours(0, 0, 0, 0)
        const due = new Date(dueDateStr)
        due.setHours(0, 0, 0, 0)
        const isOverdue = due < today
        
        if (isOverdue) {
          style = { label: 'Overdue', bg: 'bg-[#FFF1F0]', text: 'text-[#B13030]' }
        } else {
          style = { label: 'In Time', bg: 'bg-[#F5FFD8]', text: 'text-[#789C16]' }
        }
      } else {
        // No due date means not overdue, so show "In Time"
        style = { label: 'In Time', bg: 'bg-[#F5FFD8]', text: 'text-[#789C16]' }
      }
    }
    
    const badge = card.querySelector('[data-role="status-badge"]')
    if (!badge || !style) return
    badge.textContent = style.label
    // Reset to base and apply new colors
    badge.className = `px-2 py-0.5 rounded-full font-medium ${style.bg} ${style.text}`
  }

  updateCardStatusData(card, status) {
    card.dataset.capaStatus = status
    const editButton = card.querySelector('button[onclick*="openEditCapaModal"]')
    if (editButton) {
      editButton.dataset.capaStatus = status
    }
  }

  async confirmAssignedToOpen() {
    const message = 'All assigned users will be removed. Do you want to continue?'
    if (window.customConfirm) {
      try {
        return await window.customConfirm(message, {
          title: 'Confirm Status Change',
          confirmText: 'Remove',
          buttonStyle: 'danger'
        })
      } catch (error) {
        console.warn('customConfirm failed, falling back to browser confirm', error)
      }
    }
    return window.confirm(message)
  }

  dispatchToast(notificationHtmlOrMessage, type = 'error') {
    let notificationHtml = notificationHtmlOrMessage

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

    const event = new CustomEvent('toast:show', {
      detail: { notificationHtml },
      bubbles: true
    });
    document.dispatchEvent(event);
  }

  clearCardAssignees(card) {
    const chipsContainer =
      card.querySelector('[data-role="assignee-chips"]') ||
      card.querySelector('.flex.items-center.-space-x-1')

    if (chipsContainer) {
      chipsContainer.innerHTML = ''
    }

    let namesEl = card.querySelector('[data-role="assignee-names"]')
    if (!namesEl && chipsContainer && chipsContainer.parentElement) {
      const candidates = Array.from(chipsContainer.parentElement.querySelectorAll('span')).filter(span => !chipsContainer.contains(span))
      namesEl = candidates[candidates.length - 1] || null
    }

    if (namesEl) {
      namesEl.textContent = '-'
    }

    const editButton = card.querySelector('button[data-capa-assignee-ids]')
    if (editButton) {
      editButton.dataset.capaAssigneeIds = ''
      editButton.dataset.capaAssigneeNames = '[]'
      editButton.dataset.capaAssigneeRoles = '[]'
    }
  }
}


