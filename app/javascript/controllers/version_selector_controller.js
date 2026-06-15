import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["select"];

  submitForm(event) {
    event.target.form.requestSubmit();
  }

  editVersion(event) {
    event.preventDefault();

    const versionId = this.selectTarget.value;
    const standardId =
      this.element.closest('[data-controller~="version-selector"]').dataset
        .standardId || window.location.pathname.split("/").pop();

    if (!versionId) {
      alert("Please select a version first");
      return;
    }

    // Redirect to edit page with version_id parameter
    window.location.href = `/standards/${standardId}/edit?version_id=${versionId}`;
  }
}
