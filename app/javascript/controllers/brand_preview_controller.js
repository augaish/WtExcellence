import { Controller } from "@hotwired/stimulus"

// The branding form shows what a choice will look like the moment it is made:
// the chosen file appears as the logo, and the colours repaint the preview.
// Nothing is saved until Save is pressed; leaving the page discards it.
export default class extends Controller {
  static targets = ["logo", "noLogo", "primaryPicker", "primaryText", "accentPicker", "accentText", "primaryBox", "accentBox"]

  logoChanged(event) {
    const file = event.target.files && event.target.files[0]
    if (!file) return
    const url = URL.createObjectURL(file)
    this.logoTargets.forEach((img) => { img.src = url; img.classList.remove("hidden") })
    if (this.hasNoLogoTarget) this.noLogoTarget.classList.add("hidden")
  }

  primaryChanged() { this.paintPrimary(this.primaryPickerTarget.value, true) }
  primaryTyped() { this.paintPrimary(this.primaryTextTarget.value, false) }
  accentChanged() { this.paintAccent(this.accentPickerTarget.value, true) }
  accentTyped() { this.paintAccent(this.accentTextTarget.value, false) }

  paintPrimary(value, fromPicker) {
    if (!this.valid(value)) return
    if (fromPicker) this.primaryTextTarget.value = value
    else this.primaryPickerTarget.value = value
    this.primaryBoxTarget.style.backgroundColor = value
  }

  paintAccent(value, fromPicker) {
    if (!this.valid(value)) return
    if (fromPicker) this.accentTextTarget.value = value
    else this.accentPickerTarget.value = value
    this.accentBoxTarget.style.backgroundColor = value
  }

  valid(value) {
    return /^#[0-9a-fA-F]{6}$/.test(value || "")
  }
}
