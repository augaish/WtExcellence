import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["searchInput"];

  connect() {
    this.timeout = null;
  }

  perform(event) {
    clearTimeout(this.timeout);

    const query = event.target.value.trim();

    // Only search if query is at least 2 characters
    if (query.length >= 2 || query.length === 0) {
      this.timeout = setTimeout(() => {
        // Turbo will automatically handle the form submission
        event.target.form.requestSubmit();
      }, 300);
    }
  }
}
