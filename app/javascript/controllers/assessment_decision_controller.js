import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["buttons", "feedbackArea", "prompt", "input", "confirm"]

  showApprove() {
    this.show("approve", "Why are you approving this assessment?", "Approve")
  }

  showReject() {
    this.show("reject", "Why are you rejecting this assessment?", "Reject")
  }

  showReopen(event) {
    const prompt = event?.currentTarget?.dataset?.reopenPrompt || "Why are you re-evaluating this assessment?"
    const confirmLabel = event?.currentTarget?.dataset?.reopenConfirm || "Re-evaluate"
    this.show("reopen", prompt, confirmLabel)
  }

  show(action, promptText, confirmLabel) {
    this.buttonsTarget.classList.add("hidden")
    this.feedbackAreaTarget.classList.remove("hidden")
    this.promptTarget.textContent = promptText
    this.confirmTarget.textContent = confirmLabel
    this.confirmTarget.name = "assessment[commit]"
    this.confirmTarget.value = action
    this.inputTarget.value = ""
    this.inputTarget.focus()
  }

  cancel() {
    this.feedbackAreaTarget.classList.add("hidden")
    this.buttonsTarget.classList.remove("hidden")
    this.inputTarget.value = ""
  }
}
