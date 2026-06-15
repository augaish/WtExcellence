import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panelOld", "panelNew"]

  connect() {
    // Set up synchronized scrolling
    this.syncScroll = this.syncScroll.bind(this)
    
    if (this.hasPanelOldTarget && this.hasPanelNewTarget) {
      this.panelOldTarget.addEventListener('scroll', this.syncScroll)
      this.panelNewTarget.addEventListener('scroll', this.syncScroll)
    }
  }

  disconnect() {
    if (this.hasPanelOldTarget) {
      this.panelOldTarget.removeEventListener('scroll', this.syncScroll)
    }
    if (this.hasPanelNewTarget) {
      this.panelNewTarget.removeEventListener('scroll', this.syncScroll)
    }
  }

  syncScroll(event) {
    if (this._syncing) {
      return
    }

    this._syncing = true

    const sourcePanel = event.target
    const sourceContent = sourcePanel.querySelector('.panel-content')
    
    // Determine which is the other panel
    const otherPanel = sourcePanel === this.panelOldTarget ? 
      this.panelNewTarget : 
      this.panelOldTarget

    if (otherPanel) {
      const otherContent = otherPanel.querySelector('.panel-content')
      
      // Calculate scroll ratio
      const sourceScrollTop = sourcePanel.scrollTop
      const sourceScrollHeight = sourceContent.scrollHeight
      const sourceClientHeight = sourcePanel.clientHeight
      const sourceMaxScroll = sourceScrollHeight - sourceClientHeight
      
      if (sourceMaxScroll > 0) {
        const scrollRatio = sourceScrollTop / sourceMaxScroll
        
        // Apply same ratio to other panel
        const otherScrollHeight = otherContent.scrollHeight
        const otherClientHeight = otherPanel.clientHeight
        const otherMaxScroll = otherScrollHeight - otherClientHeight
        
        if (otherMaxScroll > 0) {
          otherPanel.scrollTop = scrollRatio * otherMaxScroll
        }
      }
    }

    // Allow syncing again after a short delay
    setTimeout(() => {
      this._syncing = false
    }, 10)
  }
}

