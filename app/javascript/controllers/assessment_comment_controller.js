import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button"]
  static values = { url: String }

  async post() {
    const feedback = this.inputTarget.value.trim()
    if (!feedback) return

    this.buttonTarget.disabled = true

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('[name="csrf-token"]')?.content
        },
        body: JSON.stringify({ feedback })
      })

      if (response.ok) {
        const data = await response.json()

        // Append the new comment to the list
        const list = document.getElementById("assessment-comments-list")
        const noComments = document.getElementById("assessment-no-comments")
        if (noComments) noComments.remove()

        if (list && data.html) {
          // Ensure there's a wrapping div with space-y-4
          let commentsContainer = list.querySelector(".space-y-4")
          if (!commentsContainer) {
            commentsContainer = document.createElement("div")
            commentsContainer.className = "space-y-4"
            list.appendChild(commentsContainer)
          }
          commentsContainer.insertAdjacentHTML("afterbegin", data.html)
        }

        // Clear the input
        this.inputTarget.value = ""
      } else {
        const data = await response.json().catch(() => ({}))
        this.showToast(data.error || "Failed to post comment", "error")
      }
    } catch (error) {
      console.error("Error posting comment:", error)
      this.showToast("An error occurred", "error")
    } finally {
      this.buttonTarget.disabled = false
    }
  }

  showToast(message, type) {
    const toast = document.createElement("div")
    toast.className = `fixed top-4 right-4 z-[1000] px-6 py-3 rounded-lg shadow-lg text-white font-medium transition-all duration-300 ${type === "error" ? "bg-red-600" : "bg-green-600"}`
    toast.textContent = message
    document.body.appendChild(toast)
    setTimeout(() => { toast.style.opacity = "0"; setTimeout(() => toast.remove(), 300) }, 3000)
  }
}
