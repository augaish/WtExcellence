import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "editor", "input", "pointsValue"]
  static values = {
    clauseId: String
  }

  edit(event) {
    event.preventDefault()
    this.displayTarget.classList.add("hidden")
    this.editorTarget.classList.remove("hidden")
    this.editorTarget.classList.add("flex")
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  cancel(event) {
    event.preventDefault()
    this.editorTarget.classList.add("hidden")
    this.editorTarget.classList.remove("flex")
    this.displayTarget.classList.remove("hidden")
    // Reset input to original value
    this.inputTarget.value = this.pointsValueTarget.textContent.trim() === "Not set" ? "0" : this.pointsValueTarget.textContent.trim()
  }

  async save(event) {
    event.preventDefault()
    
    const points = parseFloat(this.inputTarget.value)
    
    if (isNaN(points) || points <= 0) {
      alert("Please enter a valid number greater than 0")
      return
    }

    try {
      const response = await fetch(`/clauses/${this.clauseIdValue}/points`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
        },
        body: JSON.stringify({
          base_points: points
        })
      })

      const data = await response.json()

      if (response.ok) {
        // Update the display
        this.pointsValueTarget.textContent = Math.round(points)
        
        // Hide editor, show display
        this.editorTarget.classList.add("hidden")
        this.editorTarget.classList.remove("flex")
        this.displayTarget.classList.remove("hidden")
        
        // Show success message
        this.showNotification("Points updated and distributed successfully!", "success")
        
        // Reload the page after a short delay to show updated allocated points
        setTimeout(() => {
          window.location.reload()
        }, 1500)
      } else {
        alert(data.error || "Failed to update points")
      }
    } catch (error) {
      console.error("Error updating clause points:", error)
      alert("An error occurred while updating points")
    }
  }

  showNotification(message, type = "success") {
    // Create a simple notification
    const notification = document.createElement("div")
    notification.className = `fixed top-4 right-4 px-6 py-3 rounded-lg shadow-lg z-50 ${
      type === "success" ? "bg-green-500" : "bg-red-500"
    } text-white`
    notification.textContent = message
    
    document.body.appendChild(notification)
    
    setTimeout(() => {
      notification.remove()
    }, 3000)
  }
}

