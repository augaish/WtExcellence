import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["folderCard"]
    static values = { folderId: String }

    connect() {
        // Bind methods for event listeners
        this.boundHandleDragStart = this.handleDragStart.bind(this)
        this.boundHandleDragOver = this.handleDragOver.bind(this)
        this.boundHandleDragEnter = this.handleDragEnter.bind(this)
        this.boundHandleDragLeave = this.handleDragLeave.bind(this)
        this.boundHandleDrop = this.handleDrop.bind(this)
        this.boundHandleDragEnd = this.handleDragEnd.bind(this)

        // Add event listeners to the element itself (the folder card)
        // Use capture phase to catch events before they bubble
        this.element.addEventListener("dragstart", this.boundHandleDragStart, true)
        this.element.addEventListener("dragover", this.boundHandleDragOver, true)
        this.element.addEventListener("dragenter", this.boundHandleDragEnter, true)
        this.element.addEventListener("dragleave", this.boundHandleDragLeave, true)
        this.element.addEventListener("drop", this.boundHandleDrop, true)
        this.element.addEventListener("dragend", this.boundHandleDragEnd, true)
    }

    disconnect() {
        // Remove event listeners
        if (this.boundHandleDragStart) {
            this.element.removeEventListener("dragstart", this.boundHandleDragStart, true)
            this.element.removeEventListener("dragover", this.boundHandleDragOver, true)
            this.element.removeEventListener("dragenter", this.boundHandleDragEnter, true)
            this.element.removeEventListener("dragleave", this.boundHandleDragLeave, true)
            this.element.removeEventListener("drop", this.boundHandleDrop, true)
            this.element.removeEventListener("dragend", this.boundHandleDragEnd, true)
        }
    }

    handleDragStart(event) {
        // If the drag started from a child element (link, button), prevent it
        // Only allow dragging from the folder card itself
        const isChildElement = event.target !== this.element && this.element.contains(event.target)
        const isInteractiveElement = event.target.tagName === 'A' || 
                                     event.target.tagName === 'BUTTON' || 
                                     event.target.closest('a, button')
        
        if (isInteractiveElement) {
            event.preventDefault()
            event.stopPropagation()
            return
        }
        
        // Stop event from bubbling to prevent conflicts
        event.stopPropagation()
        
        // 1. Store the dragged folder ID in event.dataTransfer for cross-element access
        event.dataTransfer.setData("text/plain", this.folderIdValue)
        event.dataTransfer.setData("application/folder-id", this.folderIdValue)
        
        // 2. Store it in a controller property AND globally for cross-controller access
        this.draggedFolderId = this.folderIdValue
        window.draggedFolderId = this.folderIdValue // Global fallback
        
        // 3. Set effectAllowed to "move" to indicate this is a move operation
        event.dataTransfer.effectAllowed = "move"

        // 4. Add visual indicator (opacity change) to the dragged element
        this.element.classList.add("dragging")
        this.element.style.opacity = "0.5"
        this.element.style.cursor = "grabbing"

        // Add class to body to indicate dragging is active (for global styles)
        document.body.classList.add("folder-dragging-active")
    }

    handleDragOver(event) {
        // Check if this is a file upload drag (has actual files) - let file upload controller handle it
        const hasFiles = event.dataTransfer.types.includes("Files") && 
                        event.dataTransfer.files && 
                        event.dataTransfer.files.length > 0
        if (hasFiles) {
            return // Let the file upload controller handle file uploads
        }

        // Prevent default to allow drop - THIS IS CRITICAL
        event.preventDefault()
        event.stopPropagation()

        // Check if this is a file drag (upload ID) or folder drag
        const draggedUploadId = window.draggedUploadId
        const draggedFolderId = window.draggedFolderId || this.draggedFolderId
        const targetFolderId = this.folderIdValue

        // Handle file drag (upload ID)
        if (draggedUploadId && targetFolderId) {
            event.dataTransfer.dropEffect = "move"
            return
        }

        // Handle folder drag
        if (draggedFolderId && targetFolderId && this.validateDrop(draggedFolderId, targetFolderId)) {
            event.dataTransfer.dropEffect = "move"
        } else {
            event.dataTransfer.dropEffect = "none"
        }
    }

    handleDragEnter(event) {
        // Check if this is a file upload drag (has actual files) - let file upload controller handle it
        const hasFiles = event.dataTransfer.types.includes("Files") && 
                        event.dataTransfer.files && 
                        event.dataTransfer.files.length > 0
        if (hasFiles) {
            return // Let the file upload controller handle file uploads
        }

        event.preventDefault()
        event.stopPropagation()

        // Check if this is a file drag (upload ID) or folder drag
        const draggedUploadId = window.draggedUploadId
        const draggedFolderId = window.draggedFolderId || this.draggedFolderId
        const targetFolderId = this.folderIdValue

        // Handle file drag (upload ID) - always valid
        if (draggedUploadId && targetFolderId) {
            this.element.classList.add("drop-target-valid")
            return
        }

        // Handle folder drag
        if (draggedFolderId && targetFolderId && this.validateDrop(draggedFolderId, targetFolderId)) {
            this.element.classList.add("drop-target-valid")
        } else {
            this.element.classList.add("drop-target-invalid")
        }
    }

    handleDragLeave(event) {
        event.preventDefault()
        event.stopPropagation()

        // Only remove class if we're actually leaving the drop area
        if (!this.element.contains(event.relatedTarget)) {
            this.element.classList.remove("drop-target-valid", "drop-target-invalid")
        }
    }

    handleDrop(event) {
        // Check if this is a file upload drop (has actual files) - let file upload controller handle it
        const hasFiles = event.dataTransfer.files && event.dataTransfer.files.length > 0
        if (hasFiles) {
            return // Let the file upload controller handle it
        }

        event.preventDefault()
        event.stopPropagation()

        // Remove visual feedback
        this.element.classList.remove("drop-target-valid", "drop-target-invalid")

        // Check if this is a file drag (upload ID) or folder drag
        let draggedUploadId = event.dataTransfer.getData("application/upload-id") ||
                              window.draggedUploadId
        
        let draggedFolderId = event.dataTransfer.getData("application/folder-id") ||
                             this.draggedFolderId ||
                             window.draggedFolderId
        
        // If text/plain contains upload ID, use it
        const textData = event.dataTransfer.getData("text/plain")
        if (textData && !draggedUploadId && !draggedFolderId) {
            // Try to determine if it's an upload ID or folder ID
            // Upload IDs are typically UUIDs, folder IDs might be simpler
            // For now, check window variables first
            draggedUploadId = window.draggedUploadId || draggedUploadId
            draggedFolderId = window.draggedFolderId || draggedFolderId || textData
        }
        
        const targetFolderId = this.folderIdValue

        // Handle file drop (upload ID)
        if (draggedUploadId && targetFolderId) {
            this.moveFile(draggedUploadId, targetFolderId)
            return
        }

        // Handle folder drop
        if (!draggedFolderId || !targetFolderId) {
            console.error("Missing IDs - dragged folder:", draggedFolderId, "target:", targetFolderId)
            this.showError("Invalid drop. Missing information.")
            return
        }

        // Validate the drop
        if (!this.validateDrop(draggedFolderId, targetFolderId)) {
            this.showError("Invalid drop target. Cannot move folder here.")
            return
        }

        // Move the folder
        this.moveFolder(draggedFolderId, targetFolderId)
    }

    handleDragEnd(event) {
        // Clean up visual feedback
        this.element.classList.remove("dragging", "drop-target-valid", "drop-target-invalid")
        this.element.style.opacity = ""
        this.element.style.cursor = ""

        // Remove body class
        document.body.classList.remove("folder-dragging-active")

        // Clear dragged folder ID
        this.draggedFolderId = null
        window.draggedFolderId = null
    }

    isValidDropTarget(event) {
        // Get the dragged folder ID - getData doesn't work in dragover/dragenter
        // Use global variable or controller property instead
        const draggedFolderId = window.draggedFolderId || this.draggedFolderId
        const targetFolderId = this.folderIdValue

        if (!draggedFolderId || !targetFolderId) {
            return false
        }

        return this.validateDrop(draggedFolderId, targetFolderId)
    }

    validateDrop(draggedFolderId, targetFolderId) {
        // Can't drop on itself
        if (draggedFolderId === targetFolderId) {
            return false
        }

        // Note: Circular reference check (dropping into child) is handled by the backend
        // The backend will validate using the Folder model's ancestors method
        // Frontend validation here is basic - backend is the source of truth

        return true
    }

    async moveFolder(draggedFolderId, targetFolderId) {
        try {
            // Get CSRF token
            const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
            if (!csrfToken) {
                console.error('CSRF token not found')
                return
            }

            const response = await fetch(`/library/folders/${draggedFolderId}/move`, {
                method: 'PATCH',
                headers: {
                    'X-CSRF-Token': csrfToken,
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ parent_id: targetFolderId })
            })

            if (response.ok) {
                const result = await response.json()

                // Show success notification
                if (result.notification_html) {
                    this.showSuccess(result.notification_html)
                }

                // Reload page to show updated folder structure
                window.location.reload()
            } else {
                // Handle error response
                try {
                    const error = await response.json()
                    if (error.notification_html) {
                        this.showError(error.notification_html)
                    } else if (error.message) {
                        this.showError(error.message)
                    } else {
                        this.showError('Failed to move folder. Please try again.')
                    }
                } catch (parseError) {
                    console.error('Error parsing response:', parseError)
                    this.showError('Failed to move folder. Please try again.')
                }
            }
        } catch (error) {
            console.error('Move folder error:', error)
            this.showError('Network error. Please check your connection.')
        }
    }

    showSuccess(notificationHtml) {
        // Dispatch toast event (reuse existing toast system)
        const event = new CustomEvent('toast:show', {
            detail: { notificationHtml },
            bubbles: true
        })
        document.dispatchEvent(event)
    }

    async moveFile(uploadId, targetFolderId) {
        try {
            // Get CSRF token
            const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
            if (!csrfToken) {
                console.error('CSRF token not found')
                return
            }

            const response = await fetch('/library/files/move', {
                method: 'POST',
                headers: {
                    'X-CSRF-Token': csrfToken,
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ 
                    upload_id: uploadId,
                    folder_id: targetFolderId 
                })
            })

            if (response.ok) {
                const result = await response.json()

                // Show success notification
                if (result.notification_html) {
                    this.showSuccess(result.notification_html)
                }

                // Update UI using modal controller if available
                if (window.modalController && typeof window.modalController.updateFileMove === 'function') {
                    window.modalController.updateFileMove(result.upload)
                } else {
                    // Fallback: reload page to show updated file structure
                    setTimeout(() => {
                        window.location.reload()
                    }, 1000)
                }
            } else {
                // Handle error response
                try {
                    const error = await response.json()
                    if (error.notification_html) {
                        this.showError(error.notification_html)
                    } else if (error.message) {
                        this.showError(error.message)
                    } else {
                        this.showError('Failed to move file. Please try again.')
                    }
                } catch (parseError) {
                    console.error('Error parsing response:', parseError)
                    this.showError('Failed to move file. Please try again.')
                }
            }
        } catch (error) {
            console.error('Move file error:', error)
            this.showError('Network error. Please check your connection.')
        }
    }

    showError(message) {
        // Dispatch toast event with error notification
        // If message is HTML, use it directly, otherwise create a simple error message
        const event = new CustomEvent('toast:show', {
            detail: { notificationHtml: message },
            bubbles: true
        })
        document.dispatchEvent(event)
    }
}

