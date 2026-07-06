import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Admin "customize" mode for the overview dashboard.
// - Enter: reveal drag handles + hidden widgets, enable sortable reordering.
// - toggleHidden: flip a widget between shown/hidden.
// - save: POST the current order + hidden list to the active slot.
// - cancel: reload to discard unsaved changes.
export default class extends Controller {
  static targets = ["list", "widget", "handle", "editBtn", "editActions", "hint", "saveBtn", "toggleLabel"]
  static values = { slot: Number, url: String }

  connect() {
    this.editing = false
  }

  enter() {
    this.editing = true
    this.element.classList.add("is-customizing")
    this.editBtnTarget.classList.add("hidden")
    this.editActionsTarget.classList.remove("hidden")
    this.editActionsTarget.classList.add("flex")
    if (this.hasHintTarget) this.hintTarget.classList.remove("hidden")

    this.sortable = Sortable.create(this.listTarget, {
      handle: ".widget-handle",
      animation: 150,
      ghostClass: "widget-ghost",
    })
  }

  cancel() {
    window.location.reload()
  }

  toggleHidden(event) {
    if (!this.editing) return
    const widget = event.currentTarget.closest("[data-widget-key]")
    if (!widget) return
    const nowHidden = widget.dataset.widgetHidden !== "true"
    widget.dataset.widgetHidden = nowHidden ? "true" : "false"
    widget.classList.toggle("is-hidden", nowHidden)

    const label = event.currentTarget.querySelector("[data-overview-customize-target='toggleLabel']")
    if (label) {
      label.textContent = nowHidden
        ? event.currentTarget.dataset.toggleLabelShow
        : event.currentTarget.dataset.toggleLabelHide
    }
  }

  async save() {
    const widgets = Array.from(this.widgetTargets)
    const order = widgets.map((w) => w.dataset.widgetKey)
    const hidden = widgets
      .filter((w) => w.dataset.widgetHidden === "true")
      .map((w) => w.dataset.widgetKey)

    this.saveBtnTarget.disabled = true
    const token = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": token,
          Accept: "application/json",
        },
        body: JSON.stringify({ slot: this.slotValue, order: order, hidden: hidden }),
      })
      if (!response.ok) throw new Error("save failed")
      window.location.reload()
    } catch (e) {
      this.saveBtnTarget.disabled = false
      window.alert(this.saveBtnTarget.dataset.errorMessage || "Could not save the layout. Please try again.")
    }
  }
}
