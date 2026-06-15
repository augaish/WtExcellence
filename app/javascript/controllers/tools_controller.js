import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = []

    connect() {
        this.timeout = null
    }

    disconnect() {
        if (this.timeout) {
            clearTimeout(this.timeout)
        }
    }

    searchTools(event) {
        // Clear previous timeout
        if (this.timeout) {
            clearTimeout(this.timeout)
        }

        const query = event.target.value.trim()
        
        // Submit if query is empty or has 2+ characters
        if (query.length >= 2 || query.length === 0) {
            this.timeout = setTimeout(() => {
                // Turbo will automatically handle the form submission
                const form = event.target.closest('form')
                if (form) {
                    form.requestSubmit()
                }
            }, 300)
        }
    }

    submitForm(event) {
        // For select dropdowns, submit immediately
        const form = event.target.closest('form')
        if (form) {
            form.requestSubmit()
        }
    }
}