import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["tab", "content"];
  static values = { initialTab: String };

  connect() {
    // Prevent multiple initialization
    if (this.element.dataset.tabsInitialized === 'true') {
      return;
    }
    this.element.dataset.tabsInitialized = 'true';

    // Small delay to ensure DOM is fully ready
    requestAnimationFrame(() => {
      const storageKey = this.getStorageKey();
      const savedTab = localStorage.getItem(storageKey);
      const forcedTab = this.initialTabValue;
      const initialTab =
        (forcedTab && this.tabExists(forcedTab) && forcedTab) ||
        (savedTab && this.tabExists(savedTab) && savedTab) ||
        "versions";
      this.showTab(initialTab);
    });
  }

  switch(event) {
    event.preventDefault();
    const tabName = event.params.tab;
    this.showTab(tabName);
  }

  showTab(tabName) {
    this.contentTargets.forEach((content) => {
      content.classList.toggle("hidden", content.dataset.content !== tabName);
    });

    this.tabTargets.forEach((tab) => {
      const isActive = tab.dataset.tab === tabName;
      tab.classList.toggle("text-[#5C3984]", isActive);
      tab.classList.toggle("border-[#5C3984]", isActive);
      tab.classList.toggle("text-gray-500", !isActive);
      tab.classList.toggle("border-transparent", !isActive);
    });
    
    const storageKey = this.getStorageKey();
    localStorage.setItem(storageKey, tabName);
  }
  
  getStorageKey() {
    // Use the current page path as part of the key to avoid conflicts
    return `activeTab_${window.location.pathname}`;
  }
  
  tabExists(tabName) {
    return this.contentTargets.some(content => content.dataset.content === tabName);
  }
}
