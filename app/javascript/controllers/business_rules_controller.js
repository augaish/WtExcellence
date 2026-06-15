import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["rulesContainer", "ruleRow", "ruleType", "attributeSelector", "targetAttribute", "form"]

  connect() {
  }

  addRule(event) {
    event.preventDefault()
    
    const container = this.rulesContainerTarget
    const ruleCount = container.querySelectorAll('[data-business-rules-target="ruleRow"]').length
    
    const newRuleHtml = `
      <div class="mb-4 p-4 border border-gray-300 rounded-lg bg-gray-50" data-business-rules-target="ruleRow">
        <div class="flex items-start justify-between mb-3">
          <h3 class="text-sm font-semibold text-[#0D1120]">Rule ${ruleCount + 1}</h3>
          <button type="button" 
                  data-action="click->business-rules#removeRule"
                  class="text-red-600 hover:text-red-800 text-sm">
            Remove
          </button>
        </div>
        
        <div class="space-y-3">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-2">Rule Type</label>
            <select name="tool[business_rules][rules][${ruleCount}][type]" 
                    class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#5C3984] focus:border-transparent"
                    data-action="change->business-rules#ruleTypeChanged"
                    data-business-rules-target="ruleType">
              <option value="">Select rule type</option>
              <option value="average_cannot_exceed_attribute">Average of all attributes cannot exceed a specific attribute</option>
            </select>
          </div>
          
          <div data-business-rules-target="attributeSelector" class="hidden">
            <label class="block text-sm font-medium text-gray-700 mb-2">Target Attribute</label>
            <p class="text-xs text-gray-500 mb-2">Select the attribute that the average cannot exceed</p>
            <select name="tool[business_rules][rules][${ruleCount}][target_subcheckpoint_id]" 
                    class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#5C3984] focus:border-transparent"
                    data-business-rules-target="targetAttribute">
              <option value="">Select an attribute</option>
              ${this.getAttributeOptions()}
            </select>
          </div>
          
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-2">Description (optional)</label>
            <input type="text" 
                   name="tool[business_rules][rules][${ruleCount}][description]" 
                   placeholder="e.g., Average of all RADAR attributes cannot exceed Sound attribute"
                   class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#5C3984] focus:border-transparent">
          </div>
        </div>
      </div>
    `
    
    container.insertAdjacentHTML('beforeend', newRuleHtml)
    this.updateRuleNumbers()
  }

  removeRule(event) {
    event.preventDefault()
    const ruleRow = event.currentTarget.closest('[data-business-rules-target="ruleRow"]')
    if (ruleRow) {
      ruleRow.remove()
      this.updateRuleNumbers()
    }
  }

  ruleTypeChanged(event) {
    const ruleRow = event.currentTarget.closest('[data-business-rules-target="ruleRow"]')
    const attributeSelector = ruleRow.querySelector('[data-business-rules-target="attributeSelector"]')
    
    if (event.target.value === 'average_cannot_exceed_attribute') {
      attributeSelector.classList.remove('hidden')
    } else {
      attributeSelector.classList.add('hidden')
    }
  }

  updateRuleNumbers() {
    const ruleRows = this.rulesContainerTarget.querySelectorAll('[data-business-rules-target="ruleRow"]')
    ruleRows.forEach((row, index) => {
      const title = row.querySelector('h3')
      if (title) {
        title.textContent = `Rule ${index + 1}`
      }
    })
  }

  getAttributeOptions() {
    // Try to get options from an existing select element first (for show page)
    const existingSelect = this.rulesContainerTarget.querySelector('[data-business-rules-target="targetAttribute"]')
    if (existingSelect && existingSelect.options.length > 1) {
      // Clone options from existing select (skip the first "Select an attribute" option)
      let options = ''
      for (let i = 1; i < existingSelect.options.length; i++) {
        const option = existingSelect.options[i]
        options += `<option value="${option.value}">${option.text}</option>`
      }
      return options || '<option value="" disabled>No attributes available. Add checkpoints and subcheckpoints first.</option>'
    }
    
    // Fallback: Get all subcheckpoints from the form (for edit page)
    const checkpoints = document.querySelectorAll('.checkpoint')
    let options = ''
    
    checkpoints.forEach((checkpoint, cpIndex) => {
      const checkpointName = checkpoint.querySelector('input[name*="[name]"]')?.value || `Checkpoint ${cpIndex + 1}`
      const subcheckpoints = checkpoint.querySelectorAll('.subcheckpoint')
      
      subcheckpoints.forEach((subcheckpoint, scIndex) => {
        const subcheckpointName = subcheckpoint.querySelector('input[name*="subcheckpoints_attributes"][name*="[name]"]')?.value || `Subcheckpoint ${scIndex + 1}`
        const subcheckpointId = subcheckpoint.querySelector('input[name*="[id]"]')?.value
        
        if (subcheckpointId) {
          options += `<option value="${subcheckpointId}">${checkpointName} - ${subcheckpointName}</option>`
        }
      })
    })
    
    return options || '<option value="" disabled>No attributes available. Add checkpoints and subcheckpoints first.</option>'
  }
}

