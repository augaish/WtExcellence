import { Controller } from "@hotwired/stimulus"

// First-run manual welcome banner. "Start reading" dismisses the banner in the
// background (so it won't auto-show on the next login) while letting the anchor
// scroll to the topics list. Skip/close use a plain form POST instead.
export default class extends Controller {
  static values = { url: String }

  start() {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(this.urlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": token,
        Accept: "application/json",
      },
      keepalive: true,
    }).catch(() => {})
    // Let the default anchor behavior scroll to #help-topics.
  }
}
