import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["container", "choiceInput"]

    connect() {
        // Initialize nextIndex based on existing choices
        const existingChoices = this.containerTarget.querySelectorAll('[data-multiple-choice-wrapper]')
        this.nextIndex = existingChoices.length
    }

    add(event) {
        const templateId = event.target.dataset.template
        const template = document.getElementById(templateId)
        
        if (!template) {
            console.error(`Template with id "${templateId}" not found`)
            return
        }

        const clone = template.content.cloneNode(true)
        const index = this.nextIndex++

        // Replace placeholder tokens
        const replaceInNode = (node, search, replace) => {
            if (node.nodeType === Node.TEXT_NODE) {
                node.textContent = node.textContent.replace(new RegExp(search, 'g'), replace)
            } else if (node.nodeType === Node.ELEMENT_NODE) {
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

        // Find the subcheckpoint index from the parent
        const subcheckpointWrapper = event.target.closest('[data-nested-form-wrapper].subcheckpoint')
        let subcheckpointIndex = 0
        if (subcheckpointWrapper) {
            subcheckpointIndex = subcheckpointWrapper.getAttribute('subcheckpoint-index') || 0
        }

        // Find the checkpoint index
        const checkpointWrapper = subcheckpointWrapper?.closest('[data-nested-form-wrapper].checkpoint')
        let checkpointIndex = 0
        if (checkpointWrapper) {
            const checkpointNameInput = checkpointWrapper.querySelector('input[name*="[checkpoints_attributes]"][name*="[name]"]')
            if (checkpointNameInput) {
                const nameMatch = checkpointNameInput.name.match(/\[checkpoints_attributes\]\[(\d+)\]/)
                if (nameMatch) {
                    checkpointIndex = nameMatch[1]
                }
            }
        }

        replaceInNode(clone, 'CHOICE_INDEX', index)
        replaceInNode(clone, 'SUBCHECKPOINT_INDEX', subcheckpointIndex)
        replaceInNode(clone, 'CHECKPOINT_INDEX', checkpointIndex)

        this.containerTarget.appendChild(clone)
    }

    remove(event) {
        const wrapper = event.target.closest('[data-multiple-choice-wrapper]')
        
        if (!wrapper) {
            console.error('Could not find multiple choice wrapper to remove')
            return
        }

        // Check if this is an existing choice (has an index attribute)
        const indexInput = wrapper.querySelector('input[type="hidden"][name*="[index]"]')
        if (indexInput && indexInput.value) {
            // Existing choice - set _destroy to "1"
            const destroyInput = wrapper.querySelector('input[type="hidden"][name*="[_destroy]"]')
            if (destroyInput) {
                destroyInput.value = "1"
                wrapper.style.display = "none"
            }
        } else {
            // New choice - just remove it
            wrapper.remove()
        }
    }
}

