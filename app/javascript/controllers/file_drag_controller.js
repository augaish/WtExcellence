import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = { uploadId: String, fileName: String }

    connect() {
        // Make the file card draggable
        this.element.setAttribute('draggable', 'true')
        
        // Bind methods for event listeners
        this.boundHandleDragStart = this.handleDragStart.bind(this)
        this.boundHandleDragEnd = this.handleDragEnd.bind(this)

        // Add event listeners
        this.element.addEventListener("dragstart", this.boundHandleDragStart)
        this.element.addEventListener("dragend", this.boundHandleDragEnd)
    }

    disconnect() {
        if (this.boundHandleDragStart) {
            this.element.removeEventListener("dragstart", this.boundHandleDragStart)
            this.element.removeEventListener("dragend", this.boundHandleDragEnd)
        }
    }

    handleDragStart(event) {
        // Prevent dragging if clicking on interactive elements
        const isInteractiveElement = event.target.tagName === 'A' || 
                                     event.target.tagName === 'BUTTON' || 
                                     event.target.closest('a, button, input')
        
        if (isInteractiveElement) {
            event.preventDefault()
            return
        }

        // Store the upload ID in multiple formats for compatibility
        const uploadId = this.uploadIdValue
        event.dataTransfer.effectAllowed = "move"
        event.dataTransfer.setData("text/plain", uploadId)
        event.dataTransfer.setData("application/upload-id", uploadId)
        
        // Store in window for cross-frame access
        window.draggedUploadId = uploadId
        window.draggedFileName = this.fileNameValue || "File"
        
        // Add visual feedback
        this.element.classList.add("dragging")
    }

    handleDragEnd(event) {
        // Remove visual feedback
        this.element.classList.remove("dragging")
        
        // Clean up window variables
        delete window.draggedUploadId
        delete window.draggedFileName
    }
}

