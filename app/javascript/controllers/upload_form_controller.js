import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="upload-form"
export default class extends Controller {
  connect() {
    // Form is already connected via Turbo
  }

  handleSubmit(event) {
    if (event.detail.success) {
      // Show success message (you can replace with a toast notification)
      this.showSuccess("Changes saved successfully!");
    } else {
      // Handle errors if needed
      console.error("Form submission failed:", event.detail);
    }
  }

  showSuccess(message) {
    // Turbo will handle the redirect with flash messages
  }
}

