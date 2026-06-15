import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "form", "auditorSelect"]

  close() {
    this.modalTarget.close()
  }

  async submit(event) {
    event.preventDefault()

    const formData = new FormData(this.formTarget)

    try {
      const response = await fetch(this.formTarget.action, {
        method: "POST",
        body: formData,
        headers: {
          "X-CSRF-Token": document.querySelector('[name="csrf-token"]')?.content,
          "Accept": "application/json"
        }
      })

      if (response.ok) {
        this.close()
        window.location.reload()
      } else {
        const data = await response.json()
        this.showNotification(data.error || "Failed to assign auditor", "error")
      }
    } catch (error) {
      console.error("Error assigning auditor:", error)
      this.showNotification("An error occurred while assigning the auditor", "error")
    }
  }

  showNotification(message, type = "success") {
    const toast = document.createElement("div")
    toast.className = `fixed top-4 right-4 z-[1000] px-6 py-3 rounded-lg shadow-lg text-white font-medium transition-all duration-300 ${type === "success" ? "bg-green-600" : "bg-red-600"}`
    toast.textContent = message
    document.body.appendChild(toast)
    setTimeout(() => { toast.style.opacity = "1" }, 10)
    setTimeout(() => {
      toast.style.opacity = "0"
      setTimeout(() => toast.remove(), 300)
    }, 3000)
  }
}
