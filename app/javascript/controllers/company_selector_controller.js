import { Controller } from "@hotwired/stimulus"
import Choices from "choices.js"

export default class extends Controller {
  static targets = ["select", "selectedList"]

  connect() {
    this.selectedCompanyIds = new Set()
    this.choicesInstance = null

    // Initialize with already selected companies from hidden fields
    this.selectedListTarget.querySelectorAll('input[type="hidden"][name="company_ids[]"]').forEach(input => {
      this.selectedCompanyIds.add(input.value)
    })

    // Auto-initialize Choices.js if the select already has company options
    // (e.g. publish version dialog where options are server-rendered)
    if (this.selectTarget.options.length > 1) {
      // Defer slightly so the dialog has time to render and become visible
      const dialog = this.element.closest('dialog')
      if (dialog && !dialog.open) {
        // Wait for dialog to open, then init
        const observer = new MutationObserver(() => {
          if (dialog.open && !this.choicesInstance) {
            this.initChoices()
            observer.disconnect()
          }
        })
        observer.observe(dialog, { attributes: true })
        this._dialogObserver = observer
      } else {
        this.initChoices()
      }
    }
  }

  disconnect() {
    if (this._dialogObserver) {
      this._dialogObserver.disconnect()
      this._dialogObserver = null
    }
    this.destroyChoices()
  }

  destroyChoices() {
    if (this.choicesInstance) {
      this.choicesInstance.destroy()
      this.choicesInstance = null
    }
  }

  initChoices() {
    this.destroyChoices()

    const select = this.selectTarget

    this.choicesInstance = new Choices(select, {
      allowHTML: true,
      searchEnabled: true,
      shouldSort: true,
      itemSelectText: '',
      noChoicesText: 'No companies available',
      noResultsText: 'No results found',
      placeholderValue: 'Search and select a company...',
      searchPlaceholderValue: 'Type to search...',
      removeItemButton: false,
      callbackOnCreateTemplates: (template) => {
        const createItemHTML = (data, isChoice = false) => {
          if (data.placeholder) {
            return template(`
              <div class="choices__item ${isChoice ? 'choices__item--choice choices__item--placeholder' : 'choices__placeholder'}">
                ${data.label}
              </div>
            `)
          }

          const initials = data.label.substring(0, 2).toUpperCase()
          const colors = [
            'background: linear-gradient(135deg, #a78bfa, #f472b6)',
            'background: linear-gradient(135deg, #60a5fa, #22d3ee)',
            'background: linear-gradient(135deg, #fb923c, #ef4444)',
            'background: linear-gradient(135deg, #4ade80, #34d399)',
            'background: linear-gradient(135deg, #818cf8, #a78bfa)'
          ]
          const colorIndex = Math.abs(data.label.charCodeAt(0)) % colors.length
          const colorStyle = colors[colorIndex]

          const dataAttrs = isChoice
            ? `data-choice ${data.disabled ? 'data-choice-disabled aria-disabled="true"' : 'data-choice-selectable'}`
            : `data-item ${data.active ? 'aria-selected="true"' : ''}`

          return template(`
            <div class="choices__item ${isChoice ? 'choices__item--choice' : ''} ${data.highlighted ? 'is-highlighted' : ''} ${data.placeholder ? 'choices__item--placeholder' : 'choices__item--selectable'}" 
                 ${dataAttrs} 
                 data-id="${data.id}" 
                 data-value="${data.value}" 
                 ${isChoice ? 'role="option"' : ''}>
              <div class="flex items-center gap-3">
                <div class="w-7 h-7 rounded-full flex items-center justify-center text-white text-xs font-semibold flex-shrink-0" style="${colorStyle}">
                  ${initials}
                </div>
                <span class="text-sm font-medium text-[#0D1120]">${data.label}</span>
              </div>
            </div>
          `)
        }

        return {
          choice: (classNames, data) => createItemHTML(data, true),
          item: (classNames, data) => createItemHTML(data, false)
        }
      }
    })
  }

  handleSelect(event) {
    // This is called by the change event on the select
  }

  // Called when a user selects a company from the Choices dropdown
  addSelectedCompany() {
    if (!this.choicesInstance) return

    const selected = this.choicesInstance.getValue()
    if (!selected || !selected.value) return

    const companyId = String(selected.value)
    const companyName = selected.label

    // Check if already added
    if (this.selectedCompanyIds.has(companyId)) {
      this.choicesInstance.removeActiveItems()
      return
    }

    // Add to set
    this.selectedCompanyIds.add(companyId)

    // Create company card
    const companyCard = this.createCompanyCard(companyId, companyName)
    this.selectedListTarget.appendChild(companyCard)

    // Remove from choices dropdown
    const currentChoices = this.choicesInstance._store.choices.filter(c => !c.placeholder)
    const updatedChoices = currentChoices
      .filter(c => String(c.value) !== companyId)
      .map(c => ({
        value: String(c.value),
        label: c.label,
        selected: false,
        disabled: false
      }))

    this.choicesInstance.removeActiveItems()
    this.choicesInstance.setChoices(updatedChoices, 'value', 'label', true)
  }

  addCompany() {
    // Support for the "Add" button click flow (kept for backward compatibility)
    this.addSelectedCompany()
  }

  removeCompany(event) {
    event.preventDefault()
    event.stopPropagation()

    const button = event.currentTarget
    const companyId = button.dataset.companyId || button.getAttribute('data-company-id')

    // Get the card by going up to the parent (button is a direct child of the card)
    const companyCard = button.parentElement

    if (!companyCard) {
      console.error('Company card not found')
      return
    }

    if (!companyId) {
      console.error('Company ID not found on button')
      return
    }

    // Verify it's the right card by checking it has the data-company-id attribute
    if (companyCard.dataset.companyId !== companyId) {
      console.error('Card company ID mismatch')
      return
    }

    // Get company name BEFORE removing the card from DOM
    const companyNameElement = companyCard.querySelector('span.font-medium')
    const companyName = companyNameElement ? companyNameElement.textContent.trim() : ''

    // Remove from set
    this.selectedCompanyIds.delete(companyId)

    // Remove card from DOM
    companyCard.remove()

    // Add back to Choices dropdown
    if (companyName && this.choicesInstance) {
      const currentChoices = this.choicesInstance._store.choices
        .filter(c => !c.placeholder)
        .map(c => ({
          value: String(c.value),
          label: c.label,
          selected: false,
          disabled: false
        }))

      currentChoices.push({
        value: companyId,
        label: companyName,
        selected: false,
        disabled: false
      })

      // Sort alphabetically
      currentChoices.sort((a, b) => a.label.localeCompare(b.label))

      this.choicesInstance.setChoices(currentChoices, 'value', 'label', true)
    } else if (companyName) {
      // Fallback for plain select (no Choices.js)
      const select = this.selectTarget
      const option = document.createElement('option')
      option.value = companyId
      option.dataset.companyName = companyName
      option.textContent = companyName
      select.appendChild(option)
      this.sortSelectOptions(select)
    }
  }

  // Load companies into Choices.js from external data
  loadCompaniesIntoChoices(companies) {
    if (!this.choicesInstance) {
      this.initChoices()
    }

    const choices = companies.map(company => ({
      value: String(company.id),
      label: company.name,
      selected: false,
      disabled: false
    }))

    this.choicesInstance.setChoices(choices, 'value', 'label', true)
  }

  createCompanyCard(companyId, companyName) {
    const initials = companyName.substring(0, 2).toUpperCase()
    const colors = [
      'bg-gradient-to-br from-purple-400 to-pink-400',
      'bg-gradient-to-br from-blue-400 to-cyan-400',
      'bg-gradient-to-br from-orange-400 to-red-400',
      'bg-gradient-to-br from-green-400 to-emerald-400',
      'bg-gradient-to-br from-indigo-400 to-purple-400'
    ]
    const colorIndex = this.selectedCompanyIds.size % colors.length
    const colorClass = colors[colorIndex]

    // Create card container
    const card = document.createElement('div')
    card.className = 'flex items-center justify-between p-3 bg-[#F7F7FD] rounded-lg border border-[#E3E3E3]'
    card.dataset.companyId = companyId

    // Create left section with avatar and name
    const leftSection = document.createElement('div')
    leftSection.className = 'flex items-center space-x-3'

    const avatar = document.createElement('div')
    avatar.className = `w-8 h-8 rounded-full ${colorClass} flex items-center justify-center text-white text-sm font-medium`
    avatar.textContent = initials

    const nameSpan = document.createElement('span')
    nameSpan.className = 'font-medium text-[#0D1120]'
    nameSpan.textContent = companyName

    leftSection.appendChild(avatar)
    leftSection.appendChild(nameSpan)

    // Create remove button
    const removeButton = document.createElement('button')
    removeButton.type = 'button'
    removeButton.setAttribute('data-action', 'click->company-selector#removeCompany')
    removeButton.setAttribute('data-company-id', companyId)
    removeButton.className = 'text-[#FF6B6B] hover:text-red-700'

    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    svg.setAttribute('class', 'w-5 h-5')
    svg.setAttribute('fill', 'none')
    svg.setAttribute('stroke', 'currentColor')
    svg.setAttribute('viewBox', '0 0 24 24')

    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path')
    path.setAttribute('stroke-linecap', 'round')
    path.setAttribute('stroke-linejoin', 'round')
    path.setAttribute('stroke-width', '2')
    path.setAttribute('d', 'M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16')

    svg.appendChild(path)
    removeButton.appendChild(svg)

    // Create hidden input
    const hiddenInput = document.createElement('input')
    hiddenInput.type = 'hidden'
    hiddenInput.name = 'company_ids[]'
    hiddenInput.value = companyId
    hiddenInput.id = `company_${companyId}`

    // Assemble card
    card.appendChild(leftSection)
    card.appendChild(removeButton)
    card.appendChild(hiddenInput)

    return card
  }

  sortSelectOptions(select) {
    const options = Array.from(select.options)
    const firstOption = options.shift() // Remove "Choose company" option

    options.sort((a, b) => {
      return a.textContent.localeCompare(b.textContent)
    })

    // Clear and re-add
    select.innerHTML = ''
    if (firstOption) select.appendChild(firstOption)
    options.forEach(option => select.appendChild(option))
  }
}
