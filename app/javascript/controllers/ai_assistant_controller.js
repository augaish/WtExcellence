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
        loadingEl.innerHTML = this.renderAnswer(data.answer)
        this.refreshBalance(data.balance)
      } else {
        loadingEl.textContent = data.error || "Something went wrong."
      }
    } catch (error) {
      loadingEl.textContent = "Something went wrong. Please try again."
    }
  }

  // The model writes Markdown. Headings, emphasis and lists become elements;
  // everything else is escaped first, so the answer can never carry markup of
  // its own onto the page.
  renderAnswer(markdown) {
    const escape = (text) => text.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))
    const inline = (text) => escape(text)
      .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
      .replace(/(^|[^*])\*(?!\*)(.+?)\*/g, "$1<em>$2</em>")
      .replace(/`([^`]+)`/g, "<code>$1</code>")

    const blocks = []
    let list = null
    const flush = () => { if (list) { blocks.push(`<ul class="list-disc ps-5 space-y-0.5">${list.join("")}</ul>`); list = null } }

    String(markdown || "").split(/\r?\n/).forEach((line) => {
      const heading = line.match(/^#{1,6}\s+(.*)$/)
      const bullet = line.match(/^\s*(?:[-*]|\d+\.)\s+(.*)$/)
      if (heading) { flush(); blocks.push(`<p class="font-semibold mt-2">${inline(heading[1])}</p>`) }
      else if (bullet) { list = list || []; list.push(`<li>${inline(bullet[1])}</li>`) }
      else if (line.trim() === "") { flush() }
      else { flush(); blocks.push(`<p>${inline(line)}</p>`) }
    })
    flush()
    return blocks.join("")
  }

  // The charge has already happened by the time the answer arrives; the header
  // should say so without waiting for the next page.
  refreshBalance(balance) {
    if (balance === undefined || balance === null) return
    document.querySelectorAll("[data-credit-balance]").forEach((el) => { el.textContent = balance })
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
