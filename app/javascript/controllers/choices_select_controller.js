import { Controller } from "@hotwired/stimulus"
import Choices from "choices.js"

// Lightweight controller that wraps a plain <select> with Choices.js
// to add styled dropdowns and optional search.
//
// Usage (controller goes on a WRAPPER, NOT on the <select> itself):
//
//   <div data-controller="choices-select">
//     <select data-choices-select-target="select">
//       <option value="">Pick one…</option>
//       ...
//     </select>
//   </div>
//
export default class extends Controller {
    static targets = ["select"]
    static values = {
        search: { type: Boolean, default: false },
        floatDropdown: { type: Boolean, default: false }
    }

    connect() {
        this.choicesInstance = null

        // Setting select.value directly does not update the Choices widget, so a
        // form populated by JavaScript could display one value and save another.
        // Anything that assigns a value fires "choices:sync" on the select and
        // the widget is re-rendered from it.
        this._onSyncRequest = () => this.syncFromSelect()
        this.element.addEventListener("choices:sync", this._onSyncRequest)

        // Use a reliable delay to ensure the modal is open
        // and the DOM is ready for event binding.
        this._initTimer = setTimeout(() => {
            this._initChoices()
            if (this.floatDropdownValue) this._bindFloatDropdown()
        }, 100)
    }

    disconnect() {
        this.element.removeEventListener("choices:sync", this._onSyncRequest)
        if (this._initTimer) clearTimeout(this._initTimer)
        this._unbindFloatDropdown()
        this._destroyChoices()
    }

    // Makes the dropdown use position: fixed so it escapes ancestor overflow
    // clipping (e.g. inside an overflow-x-auto scroll container).
    _bindFloatDropdown() {
        const wrapper = this.element.querySelector('.choices')
        const inner = wrapper && wrapper.querySelector('.choices__inner')
        const dropdown = wrapper && wrapper.querySelector('.choices__list--dropdown')
        if (!wrapper || !dropdown) return

        this._floatWrapper = wrapper
        this._floatDropdown = dropdown

        this._positionFloat = () => {
            // Anchor to the visible input (.choices__inner) so width matches what
            // the user sees, not the outer wrapper which Choices.js sizes with
            // width: 100% once detached.
            const anchor = inner || wrapper
            const rect = anchor.getBoundingClientRect()
            const width = rect.width + 60
            dropdown.style.setProperty('position', 'fixed', 'important')
            dropdown.style.setProperty('top', `${rect.bottom}px`, 'important')
            dropdown.style.setProperty('left', `${rect.left}px`, 'important')
            dropdown.style.setProperty('width', `${width}px`, 'important')
            dropdown.style.setProperty('min-width', `${width}px`, 'important')
            dropdown.style.setProperty('max-width', `${width}px`, 'important')
            dropdown.style.setProperty('z-index', '9999', 'important')
        }
        this._resetFloat = () => {
            dropdown.style.removeProperty('position')
            dropdown.style.removeProperty('top')
            dropdown.style.removeProperty('left')
            dropdown.style.removeProperty('width')
            dropdown.style.removeProperty('min-width')
            dropdown.style.removeProperty('max-width')
            dropdown.style.removeProperty('z-index')
        }

        this._onShowDropdown = () => {
            this._positionFloat()
            window.addEventListener('scroll', this._positionFloat, true)
            window.addEventListener('resize', this._positionFloat)
        }
        this._onHideDropdown = () => {
            window.removeEventListener('scroll', this._positionFloat, true)
            window.removeEventListener('resize', this._positionFloat)
            this._resetFloat()
        }

        this.selectTarget.addEventListener('showDropdown', this._onShowDropdown)
        this.selectTarget.addEventListener('hideDropdown', this._onHideDropdown)
    }

    _unbindFloatDropdown() {
        if (this._onShowDropdown) this.selectTarget.removeEventListener('showDropdown', this._onShowDropdown)
        if (this._onHideDropdown) this.selectTarget.removeEventListener('hideDropdown', this._onHideDropdown)
        if (this._positionFloat) {
            window.removeEventListener('scroll', this._positionFloat, true)
            window.removeEventListener('resize', this._positionFloat)
        }
    }

    _initChoices() {
        if (this.choicesInstance || !this.hasSelectTarget) return

        const isMultiple = this.selectTarget.multiple
        const searchEnabled = (this.hasSearchValue ? this.searchValue : false)

        try {
            this.choicesInstance = new Choices(this.selectTarget, {
                allowHTML: true,
                searchEnabled: searchEnabled,
                shouldSort: false,
                itemSelectText: "",
                noResultsText: "No results found",
                noChoicesText: "No options available",
                removeItemButton: isMultiple,
                placeholder: true,
                placeholderValue: this.selectTarget.dataset.placeholder || "",
                searchPlaceholderValue: this.selectTarget.dataset.searchPlaceholder || "Search...",
                silent: true,
                fuseOptions: {
                    threshold: 0.1,
                    distance: 100
                }
            })

            // A sync asked for before the widget existed is applied now rather
            // than lost, since Choices initialises on a timer.
            if (this._pendingSync) {
                this.syncFromSelect()
                this._pendingSync = false
            }

            // Sync disabled state immediately
            if (this.selectTarget.disabled) {
                this.choicesInstance.disable()
            } else {
                this.choicesInstance.enable()
            }

            // Accessibility & Mobile: Ensure input is reachable
            if (isMultiple && searchEnabled && this.choicesInstance.input) {
                this.choicesInstance.input.element.placeholder = this.selectTarget.dataset.placeholder || ""
            }

        } catch (error) {
            console.error("Choices.js initialization failed:", error)
        }
    }

    _destroyChoices() {
        if (this.choicesInstance) {
            this.choicesInstance.destroy()
            this.choicesInstance = null
        }
    }

    // Public: re-render the widget from the underlying <select>'s current value.
    syncFromSelect() {
        if (!this.hasSelectTarget) return

        if (!this.choicesInstance) {
            this._pendingSync = true
            return
        }

        const value = this.selectTarget.value

        if (this.selectTarget.multiple) {
            const values = Array.from(this.selectTarget.selectedOptions).map((option) => option.value)
            this.choicesInstance.removeActiveItems()
            if (values.length) this.choicesInstance.setChoiceByValue(values)
            return
        }

        // A single select replaces its own selection; clearing it first left
        // the widget empty, which is how a Medium CAPA came to open with no
        // priority showing at all.
        this.choicesInstance.setChoiceByValue(value === null ? "" : value)
    }

    // Public: enable the select
    enable() {
        if (this.choicesInstance) {
            this.selectTarget.disabled = false
            this.choicesInstance.enable()
        }
    }

    // Public: disable the select
    disable() {
        if (this.choicesInstance) {
            this.choicesInstance.disable()
            this.selectTarget.disabled = true
        }
    }

    // Public: reset selection
    reset() {
        if (this.choicesInstance) {
            this.choicesInstance.removeActiveItems()
        }
    }

    // Public: toggle based on a checkbox event
    toggleByEvent(event) {
        const wrapper = document.getElementById("export_assignees_wrapper")

        if (event.target.checked) {
            this.enable()
            if (wrapper) wrapper.style.pointerEvents = "auto"
            if (wrapper) wrapper.style.opacity = "1"
        } else {
            this.reset()
            this.disable()
            if (wrapper) wrapper.style.pointerEvents = "none"
            if (wrapper) wrapper.style.opacity = "0.5"
        }
    }
}
