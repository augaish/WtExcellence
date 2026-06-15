import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="library-search"
export default class extends Controller {
  static targets = ["input"];

  connect() {
    this.timeout = null;
    
    // Listen for Turbo Frame loads to maintain focus
    document.addEventListener('turbo:frame-load', this.maintainFocus.bind(this));
  }

  disconnect() {
    document.removeEventListener('turbo:frame-load', this.maintainFocus.bind(this));
  }

  maintainFocus(event) {
    // Only restore focus if this is the folder_content frame
    if (event.target.id === 'folder_content' && this.hasInputTarget) {
      // Small delay to ensure frame is loaded
      setTimeout(() => {
        if (document.activeElement !== this.inputTarget) {
          this.inputTarget.focus();
          // Restore cursor position to end of text
          const length = this.inputTarget.value.length;
          this.inputTarget.setSelectionRange(length, length);
        }
      }, 50);
    }
  }

  handleSearch(event) {
    // Clear existing timeout
    if (this.timeout) {
      clearTimeout(this.timeout);
    }

    // Debounce: wait 300ms after user stops typing
    this.timeout = setTimeout(() => {
      this.submitForm();
    }, 300);
  }

  submitForm() {
    // this.element is already the form (data-controller is on the form)
    if (this.element && this.element.tagName === "FORM") {
      this.element.requestSubmit();
    }
  }
}
