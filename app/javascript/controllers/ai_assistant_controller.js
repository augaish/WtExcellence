import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="ai-assistant"
export default class extends Controller {
  static targets = ["panel", "messages", "input"]
  static values = { askUrl: String }

  toggle() {
    this.panelTarget.classList.toggle("hidden")
  }

  async submit(event) {
    event.preventDefault()
    const question = this.inputTarget.value.trim()
    if (!question) return

    this.appendMessage(question, "user")
    this.inputTarget.value = ""
    const loadingEl = this.appendMessage("...", "assistant")

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]').content
      const response = await fetch(this.askUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        body: JSON.stringify({ question })
      })
      const data = await response.json()

      if (data.success) {
        loadingEl.textContent = data.answer
      } else {
        loadingEl.textContent = data.error || "Something went wrong."
      }
    } catch (error) {
      loadingEl.textContent = "Something went wrong. Please try again."
    }
  }

  appendMessage(text, role) {
    const wrapper = document.createElement("div")
    wrapper.className = role === "user"
      ? "text-right bg-purple-50 text-[#0D1120] rounded-lg px-3 py-2 ml-6"
      : "bg-gray-50 text-gray-700 rounded-lg px-3 py-2 mr-6"
    wrapper.textContent = text
    this.messagesTarget.appendChild(wrapper)
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
    return wrapper
  }
}
