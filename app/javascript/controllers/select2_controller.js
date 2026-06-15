import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    placeholder: { type: String, default: "Select an option" },
    allowClear: { type: Boolean, default: false },
    searchEnabled: { type: Boolean, default: true }
  };

  connect() {
    if (window.$ && this.element) {
      const $select = $(this.element);
      
      // Initialize Select2 with search enabled
      $select.select2({
        placeholder: this.placeholderValue,
        allowClear: this.allowClearValue,
        width: '100%',
        dropdownParent: $select.closest('dialog, body')
      });
    }
  }

  disconnect() {
    if (window.$ && this.element) {
      const $select = $(this.element);
      if ($select.hasClass('select2-hidden-accessible')) {
        $select.select2('destroy');
      }
    }
  }
}


