import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container"]

  connect() {
    // Initialize nextIndex based on existing items to avoid conflicts
    const existingItems = this.containerTarget.querySelectorAll('[data-nested-form-wrapper]')
    this.nextIndex = existingItems.length
    // Update checkpoint numbers on initial load
    this.updateCheckpointNumbers()
  }

  nextIndex() {
    return this.nextIndex++
  }

  add(event) {
    // 1. Read the template ID from event.target.dataset.template
    const templateId = event.target.dataset.template
    
    // 2. Fetch the <template> element using document.getElementById(templateId)
    const template = document.getElementById(templateId)
    
    if (!template) {
      console.error(`Template with id "${templateId}" not found`)
      return
    }

    // 3. Clone its contents with template.content.cloneNode(true)
    const clone = template.content.cloneNode(true)
    
    // 4. Generate a new numeric index using a nextIndex() helper method inside the controller
    const index = this.nextIndex++

    // 5. Replace all placeholder tokens inside the clone
    // Helper function to replace tokens in a node tree
    const replaceInNode = (node, search, replace) => {
      if (node.nodeType === Node.TEXT_NODE) {
        node.textContent = node.textContent.replace(new RegExp(search, 'g'), replace)
      } else if (node.nodeType === Node.ELEMENT_NODE) {
        // Replace in attributes (including input name attributes)
        Array.from(node.attributes || []).forEach(attr => {
          if (attr.value.includes(search)) {
            attr.value = attr.value.replace(new RegExp(search, 'g'), replace)
          }
        })    
      }
      Array.from(node.childNodes || []).forEach(child => {
        replaceInNode(child, search, replace)
      })
    }

    // Find the correct container - if adding a subcheckpoint, find the container within the same checkpoint
    let targetContainer = this.containerTarget
    let checkpointIndex = index
    let subCheckpointIndex = 0
    
    // If adding a subcheckpoint, find the container within the closest checkpoint wrapper
    if (templateId === 'subcheckpoint-template') {
      const checkpointWrapper = event.target.closest('[data-nested-form-wrapper].checkpoint')
      if (checkpointWrapper) {
        // Find the container within this checkpointåß
        const subcheckpointContainer = checkpointWrapper.querySelector('[data-nested-form-target="container"]')
        if (subcheckpointContainer) {
          targetContainer = subcheckpointContainer
          for (let i = 0; i < subcheckpointContainer.children.length; i++) { 
            subCheckpointIndex = parseInt(subcheckpointContainer.children[i].getAttribute('subcheckpoint-index')) + 1
          }
        }
        
        // Find the checkpoint index from the parent checkpoint's input fields
        const checkpointNameInput = checkpointWrapper.querySelector('input[name*="[checkpoints_attributes]"][name*="[name]"]')
        if (checkpointNameInput) {
          const nameMatch = checkpointNameInput.name.match(/\[checkpoints_attributes\]\[(\d+)\]/)
          if (nameMatch) {
            checkpointIndex = nameMatch[1]
          }
        }
      }
      replaceInNode(clone, 'SUBCHECKPOINT_INDEX', subCheckpointIndex)
      replaceInNode(clone, 'CHECKPOINT_INDEX', checkpointIndex)
    }
    else {
      replaceInNode(clone, 'CHECKPOINT_INDEX', checkpointIndex)
    }



    // 6. Append the clone into the correct container
    // This will add it before the "Add Sub-Checkpoint" button, keeping the button at the bottom
    targetContainer.appendChild(clone)
  }

  updateCheckpointNumbers() {
    // Find the main container that holds all checkpoints (the one with data-tools--checkpoints-target="body")
    const mainContainer = document.querySelector('[data-tools--checkpoints-target="body"]')
    
    if (mainContainer) {
      // Get all visible checkpoints (not hidden/deleted ones)
      const checkpoints = Array.from(mainContainer.querySelectorAll('[data-nested-form-wrapper].checkpoint'))
      
      checkpoints.forEach((checkpoint, index) => {
        const numberSpan = checkpoint.querySelector('.checkpoint-number')
        if (numberSpan) {
          numberSpan.textContent = `${index + 1}.`
        }
      })
    }
  }

  remove(event) {
    // Find the closest wrapper element (checkpoint or subcheckpoint)
    const wrapper = event.target.closest('[data-nested-form-wrapper]')
    
    if (!wrapper) {
      console.error('Could not find nested form wrapper to remove')
      return
    }

    const isCheckpoint = wrapper.classList.contains('checkpoint')

    // Check if this is an existing record (has an ID field)
    const idInput = wrapper.querySelector('input[type="hidden"][name*="[id]"]')
    if (idInput && idInput.value) {
      // Existing record - set _destroy to "1" instead of removing
      const destroyInput = wrapper.querySelector('input[type="hidden"][name*="[_destroy]"]')
      if (destroyInput) {
        destroyInput.value = "1"
        // Hide the wrapper instead of removing it
        wrapper.style.display = "none"
      }
    } else {
      // New record - just remove it
    wrapper.remove()
    }

    // Update checkpoint numbers after removing a checkpoint
    if (isCheckpoint) {
      this.updateCheckpointNumbers()
    }
  }
}

