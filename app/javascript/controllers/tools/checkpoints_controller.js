import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["body"]

  connect() {
    // Data structure to hold checkpoints hierarchy
    this.checkpoints = []
    // Counter for generating unique IDs
    this.nextCheckpointId = 1
    this.nextSubCheckpointId = 1
    this.nextOptionId = 1
  }
}

