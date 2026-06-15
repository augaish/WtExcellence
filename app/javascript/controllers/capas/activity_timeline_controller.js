import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["line", "circle"]

  connect() {
    this.updateTimeline()
  }

  updateTimeline() {
    const circles = this.circleTargets
    if (circles.length === 0) return

    const firstCircle = circles[0]
    const lastCircle = circles[circles.length - 1]

    const firstRect = firstCircle.getBoundingClientRect()
    const lastRect = lastCircle.getBoundingClientRect()
    const containerRect = this.element.getBoundingClientRect()

    // Calculate center of first circle relative to container
    const firstCenterY = firstRect.top - containerRect.top + firstRect.height / 2
    // Calculate center of last circle relative to container
    const lastCenterY = lastRect.top - containerRect.top + lastRect.height / 2

    // Set line position and height
    const lineTop = firstCenterY
    const lineHeight = lastCenterY - firstCenterY

    this.lineTarget.style.top = `${lineTop}px`
    this.lineTarget.style.height = `${lineHeight}px`
  }
}

