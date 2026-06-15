import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="activity-tab"
export default class extends Controller {
  static targets = ["content"];

  refresh(event) {
    // Prevent the default tab switching behavior temporarily
    event.preventDefault();
    event.stopPropagation();
    
    const button = event.currentTarget;
    const capaId = this.getCapaId();
    
    if (!capaId) {
      console.error("CAPA ID not found");
      // Fallback to normal tab switch
      this.switchTab(button);
      return;
    }

    // Fetch fresh activity data
    const url = `/dashboard/capa_management/${capaId}`;
    
    fetch(url, {
      headers: {
        "Accept": "text/html",
        "X-Requested-With": "XMLHttpRequest"
      }
    })
    .then(response => response.text())
    .then(html => {
      // Parse the HTML and extract the activity tab content
      const parser = new DOMParser();
      const doc = parser.parseFromString(html, "text/html");
      const activityContent = doc.getElementById("tab-activity");
      
      if (activityContent && this.hasContentTarget) {
        // Update the content
        this.contentTarget.innerHTML = activityContent.innerHTML;
      }
      
      // Now trigger the normal tab switch
      this.switchTab(button);
    })
    .catch(error => {
      console.error("Error refreshing activity log:", error);
      // Fallback to normal tab switch
      this.switchTab(button);
    });
  }

  switchTab(button) {
    // Trigger the existing tab switching logic
    const targetTab = button.getAttribute("data-tab");
    const tabButtons = document.querySelectorAll('.tab-button');
    const tabContents = document.querySelectorAll('.tab-content');
    const validTabs = ['evidence', 'analysis', 'activity'];

    if (!validTabs.includes(targetTab)) {
      targetTab = 'evidence';
    }

    // Update active button
    tabButtons.forEach(btn => {
      btn.classList.remove('active', 'text-[#5C3984]', 'border-b-2', 'border-[#5C3984]');
      btn.classList.add('text-[#797C81]');
      
      if (btn.getAttribute('data-tab') === targetTab) {
        btn.classList.add('active', 'text-[#5C3984]', 'border-b-2', 'border-[#5C3984]');
        btn.classList.remove('text-[#797C81]');
      }
    });

    // Show/hide tab content
    tabContents.forEach(content => {
      content.classList.add('hidden');
    });
    const targetContent = document.getElementById(`tab-${targetTab}`);
    if (targetContent) {
      targetContent.classList.remove('hidden');
    }

    // Update URL hash
    if (window.location.hash.substring(1) !== targetTab) {
      const isInitialLoad = !window.location.hash || window.location.hash === '#';
      if (isInitialLoad) {
        history.replaceState(null, '', `#${targetTab}`);
      } else {
        history.pushState(null, '', `#${targetTab}`);
      }
    }
  }

  getCapaId() {
    // Extract CAPA ID from the current URL
    const match = window.location.pathname.match(/\/dashboard\/capa_management\/([^\/]+)/);
    return match ? match[1] : null;
  }
}

