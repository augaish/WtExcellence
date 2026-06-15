import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="file-upload"
export default class extends Controller {
  static targets = ["input", "fileName", "fileNameText", "fileSize"];

  triggerFileInput(event) {
    event.preventDefault();
    if (this.inputTarget) {
      this.inputTarget.click();
    }
  }

  handleFileSelect(event) {
    const file = event.target.files[0];
    if (file) {
      // Display file name
      if (this.fileNameTextTarget) {
        this.fileNameTextTarget.textContent = file.name;
      }

      // Display file size
      if (this.fileSizeTarget) {
        const fileSizeMB = (file.size / 1024 / 1024).toFixed(2);
        this.fileSizeTarget.textContent = `(${fileSizeMB} MB)`;
      }

      // Show the file name container
      if (this.fileNameTarget) {
        this.fileNameTarget.classList.remove("hidden");
      }
    } else {
      // Hide if no file selected
      if (this.fileNameTarget) {
        this.fileNameTarget.classList.add("hidden");
      }
    }
  }
}

