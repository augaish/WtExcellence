import { Controller } from "@hotwired/stimulus"

// Connect this controller to a <details> element to manage open/close behavior
export default class extends Controller {
  connect() {
    this.onDocumentClick = this.handleDocumentClick.bind(this)
    this.onKeydown = this.handleKeydown.bind(this)
    this.onToggle = this.handleToggle.bind(this)
    this.onReposition = this.reposition.bind(this)
    this.disablePortal = this.element.hasAttribute('data-no-portal')
    document.addEventListener("click", this.onDocumentClick)
    document.addEventListener("keydown", this.onKeydown)
    this.element.addEventListener("toggle", this.onToggle)
  }

  disconnect() {
    document.removeEventListener("click", this.onDocumentClick)
    document.removeEventListener("keydown", this.onKeydown)
    this.element.removeEventListener("toggle", this.onToggle)
    if (!this.disablePortal) {
      this.detachPortal()
    }
  }

  handleDocumentClick(event) {
    if (!this.element.open) return
    if (this.element.contains(event.target)) return
    this.element.open = false
  }

  handleKeydown(event) {
    if (!this.element.open) return
    if (event.key === "Escape") {
      this.element.open = false
    }
  }

  handleToggle() {
    if (this.element.open) {
      if (!this.disablePortal) {
        this.attachPortal()
        this.reposition()
        window.addEventListener("scroll", this.onReposition, true)
        window.addEventListener("resize", this.onReposition)
      }
    } else {
      if (!this.disablePortal) {
        window.removeEventListener("scroll", this.onReposition, true)
        window.removeEventListener("resize", this.onReposition)
        this.detachPortal()
      }
    }
  }

  detachPortal() {
    if (!this._portalAttached) return
    const menu = this.menuTarget || this.menuEl
    if (menu && this.placeholder && this.placeholder.parentNode) {
      this.originalParent.replaceChild(menu, this.placeholder)
    }
    if (menu) {
      menu.style.position = ""
      menu.style.top = ""
      menu.style.left = ""
      menu.style.right = ""
      menu.style.zIndex = ""
    }
    this._portalAttached = false
  }

  reposition() {
    if (this.disablePortal || !this._portalAttached) return
    const summary = this.element.querySelector("summary")
    if (!summary) return
    const rect = summary.getBoundingClientRect()
    const menu = this.menuTarget || this.menuEl
    if (!menu) return
    const menuRect = menu.getBoundingClientRect()
    const margin = 8
    const dir = getComputedStyle(document.documentElement).direction || document.documentElement.dir || document.body.dir
    const isRTL = dir === 'rtl'
    let left = isRTL ? rect.left : rect.right - menuRect.width
    let top = rect.bottom + margin
    // Keep within viewport
    left = Math.max(8, Math.min(left, window.innerWidth - menuRect.width - 8))
    top = Math.max(8, Math.min(top, window.innerHeight - menuRect.height - 8))
    // Explicitly override class-applied positioning
    menu.style.right = 'auto'
    menu.style.left = `${left}px`
    menu.style.top = `${top}px`
  }

  get menuTarget() {
    // Gracefully find the menu without requiring Stimulus targets
    if (this.menuEl && document.body.contains(this.menuEl)) return this.menuEl
    this.menuEl = this.element.querySelector('[data-capas--dropdown-target="menu"]')
    return this.menuEl
  }
  
  attachPortal() {
    if (this.disablePortal) return
    const menu = this.menuTarget
    if (!menu) return
    if (this._portalAttached) return
    this.originalParent = menu.parentNode
    this.placeholder = document.createComment("dropdown-portal-placeholder")
    this.originalParent.replaceChild(this.placeholder, menu)
    menu.style.position = "fixed"
    menu.style.zIndex = "99999"
    document.body.appendChild(menu)
    this._portalAttached = true
  }
}


