import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["input", "saveButton"];
  static values = {
    clauseId: String,
    savingLabel: { type: String, default: "Saving..." },
    savedLabel: { type: String, default: "Saved" },
    failedLabel: { type: String, default: "Failed to save" },
    networkErrorLabel: { type: String, default: "Network error: %{message}" },
    positiveError: { type: String, default: "Points must be greater than 0" },
    childrenMismatchTemplate: { type: String, default: "Children sum (%{sum}) does not match new total. Re-distribute weights below." }
  };

  async save(event) {
    event.preventDefault();
    const points = parseInt(this.inputTarget.value, 10);
    if (!Number.isFinite(points) || points <= 0) {
      this.notify(this.positiveErrorValue, "error");
      return;
    }

    const originalText = this.saveButtonTarget.textContent;
    this.saveButtonTarget.disabled = true;
    this.saveButtonTarget.textContent = this.savingLabelValue;

    try {
      const response = await fetch(`/clauses/${this.clauseIdValue}/points`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ base_points: points })
      });

      const data = await response.json();
      if (response.ok) {
        this.notify(data.message || this.savedLabelValue, "success");
        if (data.children_match === false) {
          setTimeout(() => {
            this.notify(
              this.childrenMismatchTemplateValue.replace("%{sum}", data.children_sum),
              "error"
            );
          }, 600);
        }
      } else {
        this.notify(data.error || this.failedLabelValue, "error");
      }
    } catch (e) {
      this.notify(this.networkErrorLabelValue.replace("%{message}", e.message), "error");
    } finally {
      this.saveButtonTarget.disabled = false;
      this.saveButtonTarget.textContent = originalText;
    }
  }

  notify(message, type) {
    if (typeof window.dispatchToolSwitcherToast === "function") {
      window.dispatchToolSwitcherToast(message, type);
    } else {
      console.log(`[${type}] ${message}`);
    }
  }
}
