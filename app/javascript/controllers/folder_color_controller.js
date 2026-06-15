import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["colorGrid"];

  updateColor(event) {
    const color = event.currentTarget.dataset.color; // Get color from button's data-color attribute
    const folderId = event.currentTarget.dataset.folderId;

    if (!folderId || !color) {
      console.error("Missing folder ID or color");
      return;
    }

    // Update visual selection immediately
    this.updateSelection(event.currentTarget);

    // Update the folder color via API
    fetch(`/library/folders/${folderId}/color`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
      },
      body: JSON.stringify({ color: color }),
    })
      .then((response) => response.json())
      .then((data) => {
        if (data.success) {
          // Update the folder card border color
          const folderCard = document.querySelector(`[data-folder-card-id="${folderId}"]`);
          if (folderCard) {
            folderCard.style.borderInlineStart = `4px solid ${color}`;
            folderCard.dataset.folderColor = color;
          }

          // Show notification if available
          if (data.notification_html) {
            const event = new CustomEvent("toast:show", {
              detail: { notificationHtml: data.notification_html },
              bubbles: true,
            });
            // document.dispatchEvent(event);
          }
        } else {
          // Show error message
          if (data.message) {
            alert(data.message);
          }
        }
      })
      .catch((error) => {
        console.error("Error updating folder color:", error);
        alert("An error occurred while updating the folder color.");
      });
  }

  updateSelection(selectedButton) {
    // Remove selection from all buttons in the grid
    if (this.hasColorGridTarget) {
      const buttons = this.colorGridTarget.querySelectorAll('button');
      buttons.forEach(button => {
        button.classList.remove('border-gray-800', 'ring-2', 'ring-gray-400');
        button.classList.add('border-gray-300');
        // Remove checkmark
        const svg = button.querySelector('svg');
        if (svg) {
          svg.remove();
        }
      });

      // Add selection to clicked button
      selectedButton.classList.remove('border-gray-300');
      selectedButton.classList.add('border-gray-800', 'ring-2', 'ring-gray-400');
      
      // Add checkmark
      const checkmark = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      checkmark.setAttribute('class', 'w-4 h-4 mx-auto text-white drop-shadow-lg');
      checkmark.setAttribute('fill', 'currentColor');
      checkmark.setAttribute('viewBox', '0 0 20 20');
      checkmark.innerHTML = '<path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>';
      selectedButton.appendChild(checkmark);
    }
  }
}

