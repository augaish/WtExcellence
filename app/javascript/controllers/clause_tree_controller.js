import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = { focus: String, expandChain: Array };

  connect() {
    this.initButtons();
    if (this.hasFocusValue && this.focusValue) {
      // Run after this frame so the tab content is visible and layout is settled.
      requestAnimationFrame(() => this.applyFocus());
    }
  }

  async applyFocus() {
    await this.waitUntilVisible();
    const chain = this.hasExpandChainValue ? this.expandChainValue : [];
    for (const clauseId of chain) {
      await this.expandClauseAndWait(clauseId);
    }
    this.scrollToFocus();
  }

  async waitUntilVisible() {
    for (let i = 0; i < 60; i++) {
      if (this.element.offsetParent !== null) return;
      await new Promise((resolve) => requestAnimationFrame(resolve));
    }
  }

  async expandClauseAndWait(clauseButtonId) {
    const hierarchy = document.querySelector(
      `.clause-hierarchy[data-clause-button-id="${clauseButtonId}"]`
    );
    if (!hierarchy) return;
    const containerId = hierarchy.dataset.clauseId;
    const container = document.getElementById(containerId);
    const checkpointContainer = document.getElementById(`${containerId}_checkpoints`);
    if (container) {
      container.classList.remove("collapsed");
      await this.loadChildrenIfNeeded(container);
    }
    if (checkpointContainer) {
      checkpointContainer.classList.remove("collapsed");
    }
    const button = document.getElementById(`toggle-button-${clauseButtonId}`);
    if (button) {
      button.dataset.state = "expanded";
      const icon = button.querySelector(".expand-icon");
      const label = button.querySelector(".button-text");
      if (icon) icon.style.transform = "rotate(0deg)";
      if (label) label.textContent = "Expanded";
    }
  }

  scrollToFocus() {
    const target = document.getElementById(`clause-${this.focusValue}`);
    if (!target) return;
    target.scrollIntoView({ behavior: "smooth", block: "center" });
    target.classList.add("ring-2", "ring-[#5C3984]", "ring-offset-2", "bg-[#F7F7FD]");
    setTimeout(() => {
      target.classList.remove("ring-2", "ring-[#5C3984]", "ring-offset-2", "bg-[#F7F7FD]");
    }, 2500);
  }

  initButtons() {
    document.querySelectorAll(".clause-hierarchy").forEach((clauseDiv) => {
      const clauseId = clauseDiv.dataset.clauseId;
      const container = document.getElementById(clauseId);
      const checkpointContainer = document.getElementById(
        clauseId + "_checkpoints"
      );
      const button = document.getElementById(
        `toggle-button-${clauseDiv.dataset.clauseButtonId}`
      );

      if (button && (container || checkpointContainer)) {
        const isCollapsed =
          (container && container.classList.contains("collapsed")) ||
          (checkpointContainer &&
            checkpointContainer.classList.contains("collapsed"));

        if (isCollapsed) {
          const buttonTextSpan = button.querySelector(".button-text");
          const expandIcon = button.querySelector(".expand-icon");
          if (buttonTextSpan) buttonTextSpan.textContent = "Collapsed";
          if (expandIcon) expandIcon.style.transform = "rotate(180deg)";
          button.dataset.state = "collapsed";
        }
      }
    });
  }

  toggle(event) {
    const clauseId = event.params.clauseId;
    const container = document.getElementById(clauseId);
    const checkpointContainer = document.getElementById(
      clauseId + "_checkpoints"
    );
    const button = event.currentTarget;
    const buttonTextSpan = button.querySelector(".button-text");
    const expandIcon = button.querySelector(".expand-icon");

    const isCollapsed =
      (container && container.classList.contains("collapsed")) ||
      (checkpointContainer &&
        checkpointContainer.classList.contains("collapsed"));

    if (isCollapsed) {
      if (container) {
        container.classList.remove("collapsed");
        this.loadChildrenIfNeeded(container);
      }
      if (checkpointContainer)
        checkpointContainer.classList.remove("collapsed");
      button.dataset.state = "expanded";
      buttonTextSpan.textContent = "Expanded";
      expandIcon.style.transform = "rotate(0deg)";
    } else {
      if (container) container.classList.add("collapsed");
      if (checkpointContainer) checkpointContainer.classList.add("collapsed");
      button.dataset.state = "collapsed";
      buttonTextSpan.textContent = "Collapsed";
      expandIcon.style.transform = "rotate(180deg)";
    }
  }

  async loadChildrenIfNeeded(container) {
    const src = container.dataset.lazySrc;
    if (!src || container.dataset.lazyLoaded === "true") return;
    container.dataset.lazyLoaded = "pending";
    container.innerHTML = this.lazyLoadingMarkup();
    try {
      const response = await fetch(src, {
        headers: { Accept: "text/html" },
        credentials: "same-origin",
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const html = await response.text();
      container.innerHTML = html;
      container.dataset.lazyLoaded = "true";
      delete container.dataset.lazySrc;
    } catch (err) {
      console.error("clause-tree lazy load failed:", err);
      container.dataset.lazyLoaded = "error";
      container.innerHTML = `<div class="text-sm text-red-600 py-2">Failed to load children.</div>`;
    }
  }

  lazyLoadingMarkup() {
    return `
      <div class="flex items-center gap-2 py-3 text-sm text-[#797C81]">
        <span class="inline-block w-4 h-4 border-2 border-[#5C3984]/30 border-t-[#5C3984] rounded-full animate-spin" role="status" aria-label="Loading"></span>
        <span>Loading…</span>
      </div>`;
  }

  toggleAll(event) {
    event.preventDefault();
    const button = event.currentTarget;
    const buttonText = button.querySelector(".button-text");
    const expandIcon = button.querySelector(".expand-icon");
    
    // Find the clause tree container (could be this.element or a parent container)
    const treeContainer = document.getElementById("clause-tree-container") || this.element;
    
    // Check current state - if any are expanded, we'll collapse all
    const allClauses = treeContainer.querySelectorAll(".clause-hierarchy");
    let allCollapsed = true;
    
    allClauses.forEach((clauseDiv) => {
      const clauseId = clauseDiv.dataset.clauseId;
      const container = document.getElementById(clauseId);
      const checkpointContainer = document.getElementById(
        clauseId + "_checkpoints"
      );
      
      const isCollapsed =
        (container && container.classList.contains("collapsed")) ||
        (checkpointContainer && checkpointContainer.classList.contains("collapsed"));
      
      if (!isCollapsed && (container || checkpointContainer)) {
        allCollapsed = false;
      }
    });

    // Toggle all clauses
    allClauses.forEach((clauseDiv) => {
      const clauseId = clauseDiv.dataset.clauseId;
      const container = document.getElementById(clauseId);
      const checkpointContainer = document.getElementById(
        clauseId + "_checkpoints"
      );
      const individualButton = document.getElementById(
        `toggle-button-${clauseDiv.dataset.clauseButtonId}`
      );

      if (container || checkpointContainer) {
        if (allCollapsed) {
          // Expand all
          if (container) {
            container.classList.remove("collapsed");
            this.loadChildrenIfNeeded(container);
          }
          if (checkpointContainer) checkpointContainer.classList.remove("collapsed");
          if (individualButton) {
            individualButton.dataset.state = "expanded";
            const buttonTextSpan = individualButton.querySelector(".button-text");
            const expandIcon = individualButton.querySelector(".expand-icon");
            if (buttonTextSpan) buttonTextSpan.textContent = "Expanded";
            if (expandIcon) expandIcon.style.transform = "rotate(0deg)";
          }
        } else {
          // Collapse all
          if (container) container.classList.add("collapsed");
          if (checkpointContainer) checkpointContainer.classList.add("collapsed");
          if (individualButton) {
            individualButton.dataset.state = "collapsed";
            const buttonTextSpan = individualButton.querySelector(".button-text");
            const expandIcon = individualButton.querySelector(".expand-icon");
            if (buttonTextSpan) buttonTextSpan.textContent = "Collapsed";
            if (expandIcon) expandIcon.style.transform = "rotate(180deg)";
          }
        }
      }
    });

    // Update the toggle all button
    // Get translations from data attributes or use defaults
    const collapseAllText = button.dataset.collapseAllText || "Collapse All";
    const expandAllText = button.dataset.expandAllText || "Expand All";
    
    if (allCollapsed) {
      button.dataset.state = "expanded";
      if (buttonText) buttonText.textContent = collapseAllText;
      if (expandIcon) expandIcon.style.transform = "rotate(0deg)";
    } else {
      button.dataset.state = "collapsed";
      if (buttonText) buttonText.textContent = expandAllText;
      if (expandIcon) expandIcon.style.transform = "rotate(180deg)";
    }
  }
}
