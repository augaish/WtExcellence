import { Controller } from "@hotwired/stimulus"
import Choices from "choices.js"

export default class extends Controller {
  static targets = ["versionSelect", "companySelector", "form"]
  static values = {
    noVersionsOption: String,
    noVersionsMessage: String,
    loading: String,
    errorStandardId: String,
    errorLoadingVersions: String,
    loadingCompanies: String,
    noAvailableCompanies: String,
    errorLoadingCompanies: String
  }

  connect() {
    // Reset standard ID when modal closes
    this.element.addEventListener('close', this.handleClose.bind(this))
    this.standardId = null
    this.versionChoices = null
  }

  disconnect() {
    this.element.removeEventListener('close', this.handleClose.bind(this))
  }

  // Called when modal opens - get standard ID from the button that triggered it
  open(event) {
    // Get the button that triggered the modal
    // event.target might be the SVG icon, so we need to find the button element
    let button = event?.target || event?.currentTarget

    // If target is not the button (e.g., it's an SVG icon inside), find the button
    if (button && !button.hasAttribute('data-standard-id')) {
      button = button.closest('button[data-standard-id]') ||
        button.closest('[data-standard-id]') ||
        button
    }

    // Try to get standard ID from button
    let standardId = button?.dataset?.standardId ||
      button?.getAttribute?.('data-standard-id')

    // If still not found, try to find it in the card that contains the button
    if (!standardId && button) {
      const card = button.closest('[data-standard-id]')
      standardId = card?.dataset?.standardId || card?.getAttribute?.('data-standard-id')
    }

    if (standardId) {
      this.standardId = standardId
      this.updateFormUrl(standardId)
      this.loadVersions(standardId)
    } else {
      console.error('No standard ID found. Button:', button, 'Event:', event)
      // Show error message in the select
      if (this.hasVersionSelectTarget) {
        const errorText = this.errorStandardIdValue || 'Error: Could not find standard ID'
        this.versionSelectTarget.innerHTML = `<option value="">${errorText}</option>`
        this.versionSelectTarget.disabled = true
      }
    }
  }

  updateFormUrl(standardId) {
    if (this.hasFormTarget) {
      this.formTarget.action = `/standards/${standardId}/assign`
    }
    // Also update hidden standard_id field if it exists
    const standardIdInput = this.formTarget?.querySelector('[data-assign-standard-target="standardIdInput"]')
    if (standardIdInput) {
      standardIdInput.value = standardId
    }
  }

  handleClose() {
    // Destroy Choices instance
    if (this.versionChoices) {
      this.versionChoices.destroy()
      this.versionChoices = null
    }

    // Clear the select when modal closes
    if (this.hasVersionSelectTarget) {
      const loadingText = this.loadingValue || 'Loading'
      this.versionSelectTarget.innerHTML = `<option value="">${loadingText}...</option>`
      this.versionSelectTarget.value = ''
    }
    // Clear companies
    this.clearCompanies()
    this.standardId = null
  }

  async loadVersions(standardId) {
    if (!this.hasVersionSelectTarget) return

    // Show loading state
    const loadingText = this.loadingValue || 'Loading'
    this.versionSelectTarget.innerHTML = `<option value="">${loadingText}...</option>`
    this.versionSelectTarget.disabled = true

    try {
      const response = await fetch(`/standards/${standardId}/versions.json`)
      if (!response.ok) throw new Error('Failed to load versions')

      const data = await response.json()
      const versions = data.versions || []

      // Clear and populate select
      this.versionSelectTarget.innerHTML = ''

      if (versions.length === 0) {
        const noVersionsText = this.noVersionsOptionValue || 'No published versions available'
        this.versionSelectTarget.innerHTML = `<option value="">${noVersionsText}</option>`
        this.versionSelectTarget.disabled = true
        // Hide company selector when no versions available
        this.showNoVersionsMessage()
      } else {
        this.versionSelectTarget.disabled = false
        // Show company selector
        this.hideNoVersionsMessage()
        versions.forEach(version => {
          const option = document.createElement('option')
          option.value = version.id
          option.textContent = version.version_label
          if (version.is_latest) {
            option.selected = true
            // Load companies for the default selected version
            this.loadCompanies(version.id)
          }
          this.versionSelectTarget.appendChild(option)
        })
      }
    } catch (error) {
      console.error('Error loading versions:', error)
      const errorText = this.errorLoadingVersionsValue || 'Error loading versions'
      this.versionSelectTarget.innerHTML = `<option value="">${errorText}</option>`
      this.versionSelectTarget.disabled = true
      this.showNoVersionsMessage()
    } finally {
      // Re-initialize Choices.js if we have versions
      if (this.versionSelectTarget.options.length > 0 && !this.versionSelectTarget.disabled) {
        if (this.versionChoices) this.versionChoices.destroy()
        this.versionChoices = new Choices(this.versionSelectTarget, {
          allowHTML: true,
          searchEnabled: true,
          shouldSort: false,
          itemSelectText: '',
          placeholder: true
        })
      }
    }
  }

  onVersionChange(event) {
    const versionId = event.target.value
    if (versionId) {
      this.loadCompanies(versionId)
    } else {
      this.clearCompanies()
    }
  }

  async loadCompanies(versionId) {
    if (!this.hasCompanySelectorTarget) return

    const companySelector = this.companySelectorTarget
    const select = companySelector.querySelector('[data-company-selector-target="select"]')
    const selectedList = companySelector.querySelector('[data-company-selector-target="selectedList"]')

    if (!select) return

    // Get the company-selector controller instance
    const companySelectorController = this.application.getControllerForElementAndIdentifier(companySelector, 'company-selector')

    // Destroy existing Choices instance while loading
    if (companySelectorController) {
      companySelectorController.destroyChoices()
    }

    // Show loading state (on plain select while loading)
    const loadingCompaniesText = this.loadingCompaniesValue || 'Loading companies'
    select.innerHTML = `<option value="">${loadingCompaniesText}...</option>`
    select.disabled = true

    try {
      const response = await fetch(`/standards/${this.standardId}/versions/${versionId}/available_companies.json`)
      if (!response.ok) throw new Error('Failed to load companies')

      const data = await response.json()
      const companies = data.companies || []

      // Clear and populate select
      select.innerHTML = `<option value="">${this.element.querySelector('[data-company-selector-target="select"]')?.querySelector('option[value=""]')?.textContent || 'Choose company'}</option>`
      select.disabled = false

      // Clear selected companies list and reset company-selector controller
      selectedList.innerHTML = ''
      if (companySelectorController) {
        companySelectorController.selectedCompanyIds = new Set()
      }

      if (companies.length === 0) {
        const noCompaniesText = this.noAvailableCompaniesValue || 'No available companies'
        select.innerHTML = `<option value="">${noCompaniesText}</option>`
        // Still init Choices for consistent UI, just with empty state
        if (companySelectorController) {
          companySelectorController.initChoices()
        }
      } else {
        // Add options to the plain select first
        companies.forEach(company => {
          const option = document.createElement('option')
          option.value = company.id
          option.dataset.companyName = company.name
          option.textContent = company.name
          select.appendChild(option)
        })
        // Then initialize Choices.js on top of the populated select
        if (companySelectorController) {
          companySelectorController.initChoices()
        }
      }
    } catch (error) {
      console.error('Error loading companies:', error)
      const errorText = this.errorLoadingCompaniesValue || 'Error loading companies'
      select.innerHTML = `<option value="">${errorText}</option>`
      select.disabled = false
    }
  }

  clearCompanies() {
    if (!this.hasCompanySelectorTarget) return

    const companySelector = this.companySelectorTarget
    const select = companySelector.querySelector('[data-company-selector-target="select"]')
    const selectedList = companySelector.querySelector('[data-company-selector-target="selectedList"]')

    // Destroy Choices.js instance first
    const companySelectorController = this.application.getControllerForElementAndIdentifier(companySelector, 'company-selector')
    if (companySelectorController) {
      companySelectorController.destroyChoices()
      companySelectorController.selectedCompanyIds = new Set()
    }

    if (select) {
      const chooseCompanyText = 'Choose company'
      select.innerHTML = `<option value="">${chooseCompanyText}</option>`
    }
    if (selectedList) {
      selectedList.innerHTML = ''
    }
  }

  showNoVersionsMessage() {
    const content = this.element.querySelector('[data-assign-standard-target="content"]')
    if (!content) return

    // Hide company selector if it exists
    if (this.hasCompanySelectorTarget) {
      this.companySelectorTarget.style.display = 'none'
    }

    // Show message if it doesn't exist
    let messageDiv = content.querySelector('[data-assign-standard-target="noVersionsMessage"]')
    if (!messageDiv) {
      messageDiv = document.createElement('div')
      messageDiv.setAttribute('data-assign-standard-target', 'noVersionsMessage')
      messageDiv.className = 'text-center py-8 text-gray-500'
      messageDiv.textContent = this.noVersionsMessageValue || 'No published versions available for this standard.'
      content.appendChild(messageDiv)
    } else {
      messageDiv.style.display = 'block'
    }
  }

  hideNoVersionsMessage() {
    const content = this.element.querySelector('[data-assign-standard-target="content"]')
    if (!content) return

    // Show company selector if it exists
    if (this.hasCompanySelectorTarget) {
      this.companySelectorTarget.style.display = 'block'
    }

    // Hide message if it exists
    const messageDiv = content.querySelector('[data-assign-standard-target="noVersionsMessage"]')
    if (messageDiv) {
      messageDiv.style.display = 'none'
    }
  }
}

