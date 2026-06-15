import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["childInput", "sum", "status", "saveButton", "rollupButton"];
  static values = {
    parentId: String,
    parentPoints: Number,
    savingLabel: { type: String, default: "Saving..." },
    savedLabel: { type: String, default: "Saved" },
    failedLabel: { type: String, default: "Failed to save" },
    networkErrorTemplate: { type: String, default: "Network error: %{message}" },
    setParentFirst: { type: String, default: "set parent weight first" },
    matches: { type: String, default: "✓ matches" },
    overTemplate: { type: String, default: "%{n} over" },
    remainingTemplate: { type: String, default: "%{n} remaining" },
    positiveError: { type: String, default: "Sum of sub-clause weights must be greater than 0" },
    confirmTemplate: { type: String, default: "Set parent total to %{sum} pts and save?" },
    grandparentMismatch: { type: String, default: "Grandparent's children no longer sum correctly — re-balance one level up." }
  };

  connect() {
    this.recalculate();
  }

  recalculate() {
    const sum = this.childInputTargets.reduce((acc, input) => {
      const v = parseInt(input.value, 10);
      return acc + (Number.isFinite(v) ? v : 0);
    }, 0);

    if (this.hasSumTarget) {
      this.sumTarget.textContent = this.format(sum);
    }

    const target = this.parentPointsValue;
    const diff = sum - target;
    const matches = target > 0 && diff === 0;

    if (this.hasStatusTarget) {
      if (target <= 0) {
        this.statusTarget.textContent = this.setParentFirstValue;
        this.statusTarget.className = "text-xs font-medium text-amber-600";
      } else if (matches) {
        this.statusTarget.textContent = this.matchesValue;
        this.statusTarget.className = "text-xs font-medium text-green-600";
      } else if (diff > 0) {
        this.statusTarget.textContent = this.overTemplateValue.replace("%{n}", this.format(diff));
        this.statusTarget.className = "text-xs font-medium text-red-600";
      } else {
        this.statusTarget.textContent = this.remainingTemplateValue.replace("%{n}", this.format(-diff));
        this.statusTarget.className = "text-xs font-medium text-amber-600";
      }
    }

    if (this.hasSaveButtonTarget) {
      this.saveButtonTarget.disabled = !matches;
    }
  }

  format(n) {
    return Math.trunc(n).toString();
  }

  async save(event) {
    event.preventDefault();
    if (this.saveButtonTarget.disabled) return;

    const weights = {};
    this.childInputTargets.forEach((input) => {
      const id = input.dataset.clauseId;
      if (!id) return;
      weights[id] = parseInt(input.value, 10) || 0;
    });

    const originalText = this.saveButtonTarget.textContent;
    this.saveButtonTarget.disabled = true;
    this.saveButtonTarget.textContent = this.savingLabelValue;

    try {
      const response = await fetch(`/clauses/${this.parentIdValue}/distribute_weights`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ weights })
      });

      const data = await response.json();
      if (response.ok) {
        this.notify(data.message || this.savedLabelValue, "success");
      } else {
        this.notify(data.error || this.failedLabelValue, "error");
      }
    } catch (e) {
      this.notify(this.networkErrorTemplateValue.replace("%{message}", e.message), "error");
    } finally {
      this.saveButtonTarget.textContent = originalText;
      this.recalculate();
    }
  }

  async rollup(event) {
    event.preventDefault();

    const weights = {};
    let sum = 0;
    this.childInputTargets.forEach((input) => {
      const id = input.dataset.clauseId;
      if (!id) return;
      const v = parseInt(input.value, 10) || 0;
      weights[id] = v;
      sum += v;
    });

    if (sum <= 0) {
      this.notify(this.positiveErrorValue, "error");
      return;
    }

    if (!confirm(this.confirmTemplateValue.replace("%{sum}", this.format(sum)))) return;

    const originalText = this.rollupButtonTarget.textContent;
    this.rollupButtonTarget.disabled = true;
    this.rollupButtonTarget.textContent = this.savingLabelValue;

    try {
      const response = await fetch(`/clauses/${this.parentIdValue}/rollup_weights`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ weights })
      });

      const data = await response.json();
      if (response.ok) {
        this.notify(data.message || this.savedLabelValue, "success");
        const reloadDelay = data.grandparent_match === false ? 1500 : 600;
        if (data.grandparent_match === false) {
          this.notify(this.grandparentMismatchValue, "error");
        }
        setTimeout(() => window.location.reload(), reloadDelay);
      } else {
        this.notify(data.error || this.failedLabelValue, "error");
        this.rollupButtonTarget.disabled = false;
        this.rollupButtonTarget.textContent = originalText;
      }
    } catch (e) {
      this.notify(this.networkErrorTemplateValue.replace("%{message}", e.message), "error");
      this.rollupButtonTarget.disabled = false;
      this.rollupButtonTarget.textContent = originalText;
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
