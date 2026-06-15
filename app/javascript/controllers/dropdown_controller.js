import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["menu"];
  static values = { fixed: { type: Boolean, default: false } };

  connect() {
    // Close dropdown when clicking outside
    this.boundHandleClickOutside = this.handleClickOutside.bind(this);
    document.addEventListener("click", this.boundHandleClickOutside);
  }

  disconnect() {
    document.removeEventListener("click", this.boundHandleClickOutside);
  }

  toggle(event) {
    event.stopPropagation();
    const isOpening = this.menuTarget.classList.contains("hidden");
    if (isOpening && this.fixedValue) {
      this.positionMenuFixed(event.currentTarget);
    }
    if (!this.fixedValue) {
      this.menuTarget.style.position = "";
      this.menuTarget.style.top = "";
      this.menuTarget.style.left = "";
      this.menuTarget.style.right = "";
    }
    this.menuTarget.classList.toggle("hidden");
  }

  positionMenuFixed(trigger) {
    const rect = trigger.getBoundingClientRect();
    const viewportPadding = 8;
    const gap = 4;

    // Reset any previous height cap so the next measurement reflects the natural size.
    this.menuTarget.style.maxHeight = "";
    this.menuTarget.style.overflowY = "";

    // Measure menu dimensions even when hidden.
    const wasHidden = this.menuTarget.classList.contains("hidden");
    if (wasHidden) {
      this.menuTarget.classList.remove("hidden");
      this.menuTarget.style.visibility = "hidden";
      this.menuTarget.style.position = "fixed";
    }
    const menuWidth = this.menuTarget.offsetWidth || 160;
    const menuHeight = this.menuTarget.offsetHeight || 0;
    if (wasHidden) {
      this.menuTarget.classList.add("hidden");
      this.menuTarget.style.visibility = "";
    }

    // Horizontal: keep menu fully inside viewport (works for both LTR and RTL pages).
    const preferredLeft = rect.right - menuWidth;
    const maxLeft = window.innerWidth - menuWidth - viewportPadding;
    const left = Math.max(viewportPadding, Math.min(preferredLeft, maxLeft));

    // Vertical: prefer below, flip above when there isn't enough room and more space exists above.
    const spaceBelow = window.innerHeight - rect.bottom - viewportPadding - gap;
    const spaceAbove = rect.top - viewportPadding - gap;
    const openUp = menuHeight > spaceBelow && spaceAbove > spaceBelow;
    const available = Math.max(openUp ? spaceAbove : spaceBelow, 0);

    if (menuHeight > available) {
      this.menuTarget.style.maxHeight = `${Math.max(available, 80)}px`;
      this.menuTarget.style.overflowY = "auto";
    }

    const effectiveHeight = Math.min(menuHeight, available || menuHeight);
    const top = openUp
      ? Math.max(viewportPadding, rect.top - gap - effectiveHeight)
      : rect.bottom + gap;

    this.menuTarget.style.position = "fixed";
    this.menuTarget.style.top = `${top}px`;
    this.menuTarget.style.left = `${left}px`;
    this.menuTarget.style.right = "auto";
  }

  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.menuTarget.classList.add("hidden");
    }
  }

}
