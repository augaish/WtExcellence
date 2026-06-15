import { Controller } from "@hotwired/stimulus"


export default class extends Controller {
    static targets = ["dropArea"]
    static values = { folderId: String, legalDocuments: Boolean }

    connect() {
        // Check if target exists before adding listeners
        if (this.hasDropAreaTarget) {
            // Bind methods once and store references for cleanup
            this.boundHandleDragEnter = this.handleDragEnter.bind(this)
            this.boundHandleDragOver = this.handleDragOver.bind(this)
            this.boundHandleDragLeave = this.handleDragLeave.bind(this)
            this.boundHandleDrop = this.handleDrop.bind(this)

            // Track drag depth to handle nested elements
            this.dragDepth = 0

            document.body.addEventListener("dragenter", this.boundHandleDragEnter)
            document.body.addEventListener("dragover", this.boundHandleDragOver)
            document.body.addEventListener("dragleave", this.boundHandleDragLeave)
            document.body.addEventListener("drop", this.boundHandleDrop)

            // Create upload status indicator
            this.createUploadIndicator()
        }
    }

    disconnect() {
        if (this.hasDropAreaTarget && this.boundHandleDragEnter) {
            document.body.removeEventListener("dragenter", this.boundHandleDragEnter)
            document.body.removeEventListener("dragover", this.boundHandleDragOver)
            document.body.removeEventListener("dragleave", this.boundHandleDragLeave)
            document.body.removeEventListener("drop", this.boundHandleDrop)
        }
        // Remove upload indicator if it exists
        if (this.uploadIndicator) {
            this.uploadIndicator.remove()
            this.uploadIndicator = null
        }
    }

    handleDragEnter(event) {
        // Only handle file drags, ignore other drags (like folder drags)
        if (!event.dataTransfer.types.includes("Files")) {
            return
        }
        
        event.preventDefault()
        event.stopPropagation()
        
        this.dragDepth++
        
        // When file first enters the page, highlight the drop zone
        if (this.dragDepth === 1) {
            this.dropAreaTarget.classList.add("drag-over", "file-drag-active")
            this.showDropZoneMessage()
        }
    }

    handleDragOver(event) {
        // Only handle file drags
        if (!event.dataTransfer.types.includes("Files")) {
            return
        }
        
        event.preventDefault()
        event.stopPropagation()
    }

    handleDragLeave(event) {
        // Only handle file drags
        if (!event.dataTransfer.types.includes("Files")) {
            return
        }
        
        event.preventDefault()
        event.stopPropagation()
        
        this.dragDepth--
        
        // When file leaves the page completely, remove highlight
        if (this.dragDepth === 0) {
            this.dropAreaTarget.classList.remove("drag-over", "file-drag-active")
            this.hideDropZoneMessage()
        }
    }

    handleDrop(event) {
        // Only handle file drops
        if (!event.dataTransfer.types.includes("Files")) {
            return
        }
        
        event.preventDefault()
        event.stopPropagation()
        
        // Reset drag depth
        this.dragDepth = 0
        this.dropAreaTarget.classList.remove("drag-over", "file-drag-active")
        this.hideDropZoneMessage()
        
        const files = event.dataTransfer.files
        if (!files || files.length === 0) {
            return
        }

        // Show uploading indicator
        this.showUploadIndicator(files.length)

        // Process files - send them one at a time since controller expects single file
        // Or send all files sequentially
        const uploadPromises = []
        for (const file of files) {
            // Create FormData for each file (controller expects nested structure)
            const formData = new FormData()
            
            // Append file with nested structure: upload[file]
            formData.append('upload[file]', file)

            // Get folder_id from Stimulus value if set
            if (this.hasFolderIdValue && this.folderIdValue) {
                formData.append('upload[folder_id]', this.folderIdValue)
            }
            
            // Set visibility based on context
            if (this.hasLegalDocumentsValue && this.legalDocumentsValue) {
                // Set visibility to private if uploading to Legal Documents
                formData.append('upload[visibility]', 'private')
            } else {
                // Default to public for other folders
                formData.append('upload[visibility]', 'public')
            }

            // Send file to server
            uploadPromises.push(this.uploadFiles(formData))
        }

        // Wait for all uploads to complete
        Promise.allSettled(uploadPromises).then(() => {
            // Hide uploading indicator after a short delay
            setTimeout(() => {
                this.hideUploadIndicator()
            }, 500)
        })
    }


    async uploadFiles(formData) {
        try {
            // Get CSRF token
            const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
            if (!csrfToken) {
                console.error('CSRF token not found')
                this.hideUploadIndicator()
                return
            }

            const response = await fetch('/uploads', {
                method: 'POST',
                headers: {
                    'X-CSRF-Token': csrfToken
                    // Don't set Content-Type - let browser set it with boundary for FormData
                },
                body: formData
            })

            if (response.ok) {
                const result = await response.json()
                
                // Show success notification
                if (result.notification_html) {
                    this.showSuccess(result.notification_html)
                }
                
                // Reload page to show new files
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
                        this.showError('Upload failed. Please try again.')
                    }
                } catch (parseError) {
                    console.error('Error parsing response:', parseError)
                    this.showError('Upload failed. Please try again.')
                }
                this.hideUploadIndicator()
            }
        } catch (error) {
            console.error('Upload error:', error)
            this.showError('Network error. Please check your connection.')
            this.hideUploadIndicator()
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

    showError(notificationHtml) {
        // Dispatch toast event with error notification
        const event = new CustomEvent('toast:show', {
            detail: { notificationHtml },
            bubbles: true
        })
        document.dispatchEvent(event)
    }

    showDropZoneMessage() {
        if (this.hasDropAreaTarget) {
            // Add a visual indicator message to the drop zone
            let messageEl = this.dropAreaTarget.querySelector('.drop-zone-message')
            if (!messageEl) {
                messageEl = document.createElement('div')
                messageEl.className = 'drop-zone-message'
                messageEl.innerHTML = `
                    <div class="drop-zone-message-content">
                        <svg class="drop-zone-icon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"/>
                        </svg>
                        <span>Drop files here to upload</span>
                    </div>
                `
                this.dropAreaTarget.appendChild(messageEl)
            }
            messageEl.style.display = 'flex'
        }
    }

    hideDropZoneMessage() {
        if (this.hasDropAreaTarget) {
            const messageEl = this.dropAreaTarget.querySelector('.drop-zone-message')
            if (messageEl) {
                messageEl.style.display = 'none'
            }
        }
    }

    createUploadIndicator() {
        // Create a floating upload indicator
        const indicator = document.createElement('div')
        indicator.id = 'upload-indicator'
        indicator.className = 'upload-indicator'
        indicator.innerHTML = `
            <div class="upload-indicator-content">
                <div class="upload-spinner"></div>
                <span class="upload-text">Uploading...</span>
            </div>
        `
        document.body.appendChild(indicator)
        this.uploadIndicator = indicator
    }

    showUploadIndicator(fileCount = 1) {
        if (this.uploadIndicator) {
            const textEl = this.uploadIndicator.querySelector('.upload-text')
            if (textEl) {
                textEl.textContent = fileCount > 1 
                    ? `Uploading ${fileCount} files...` 
                    : 'Uploading...'
            }
            this.uploadIndicator.classList.add('active')
        }
    }

    hideUploadIndicator() {
        if (this.uploadIndicator) {
            this.uploadIndicator.classList.remove('active')
        }
    }
}