import { Controller } from "@hotwired/stimulus"
import Choices from "choices.js"

export default class extends Controller {
    static targets = ["select"]

    connect() {
        console.log("Capas Filter Controller connected");

        try {
            // Check if select target exists
            if (!this.hasSelectTarget) {
                console.error("Select target not found");
                return;
            }

            // Check if Choices is loaded
            if (typeof Choices === 'undefined') {
                console.error("Choices.js is not loaded or undefined");
                this.fallback();
                return;
            }

            this.choices = new Choices(this.selectTarget, {
                searchEnabled: true,
                searchPlaceholderValue: "Search users...",
                itemSelectText: '',
                shouldSort: false,
                placeholder: true,
                // For select elements, the first option with value="" acts as placeholder
                // placeholderValue: this.element.dataset.placeholder, 
                removeItemButton: false, // Disabled for single select to avoid issues
                allowHTML: true,
            });
            console.log("Choices initialized successfully");

            // Ensure change event triggers submit
            this.selectTarget.addEventListener('change', this.submit.bind(this));

        } catch (error) {
            console.error('Error initializing Choices.js:', error);
            this.fallback();
        }
    }

    fallback() {
        console.log("Falling back to native select");
        if (this.hasSelectTarget) {
            this.selectTarget.classList.remove('appearance-none');
            this.selectTarget.style.display = 'block'; // Ensure it's visible if Choices hid it partly
        }
    }

    disconnect() {
        if (this.choices) {
            this.choices.destroy();
        }
    }

    submit() {
        console.log("Submitting form");
        if (this.hasSelectTarget && this.selectTarget.form) {
            this.selectTarget.form.requestSubmit();
        }
    }
}
