import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "submitBtn", "list", "confirmDialog", "confirmMessage"]
  static values = {
    viewOneReply: { type: String, default: "View 1 reply" },
    viewNReplies: { type: String, default: "View %{count} replies" },
    confirmDeleteComment: { type: String, default: "Delete this comment? All replies will be removed." },
    confirmDeleteReply: { type: String, default: "Delete this reply?" }
  }

  connect() {
    this.capaId = this.element.dataset.capaId
    this.capaActionId = this.element.dataset.capaActionId
    this.csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    this.pendingDelete = null
    this.inputTarget?.addEventListener("input", () => this.toggleSubmit())
    this.toggleSubmit()
    this.bindReplyButtons()
    this.bindDeleteButtons()
    if (this.hasConfirmDialogTarget) {
      this.confirmDialogTarget.addEventListener("click", (e) => {
        if (e.target === this.confirmDialogTarget) this.cancelDelete()
      })
    }
  }

  toggleSubmit() {
    if (!this.hasSubmitBtnTarget) return
    const text = (this.inputTarget?.value || "").trim()
    this.submitBtnTarget.disabled = !text
  }

  maybeSubmit(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.submitRoot()
    }
  }

  async submitRoot() {
    if (!this.hasInputTarget || !this.hasSubmitBtnTarget) return
    const body = (this.inputTarget.value || "").trim()
    if (!body) return
    await this.postComment(body, null)
    this.inputTarget.value = ""
    this.toggleSubmit()
  }

  async postComment(body, parentId) {
    const url = `/dashboard/capa_management/${this.capaId}/capa_actions/${this.capaActionId}/comments`
    const payload = { comment: { body, parent_id: parentId } }
    const opts = {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": this.csrfToken
      },
      body: JSON.stringify(payload)
    }
    const res = await fetch(url, opts)
    const data = await res.json().catch(() => ({}))
    if (res.ok && data.success) {
      if (data.notification_html) {
        document.dispatchEvent(new CustomEvent("toast:show", { detail: { notificationHtml: data.notification_html }, bubbles: true }))
      }
      if (parentId) {
        const form = this.element.querySelector(`.reply-form[data-reply-to="${parentId}"]`)
        if (form) {
          const ta = form.querySelector("textarea")
          if (ta) ta.value = ""
          form.classList.add("hidden")
        }
        if (data.reply_html && data.parent_id) {
          const parentCard = this.element.querySelector(`[data-comment-id="${data.parent_id}"]`)
          if (parentCard) {
            let repliesContainer = parentCard.querySelector(".comment-replies-container")
            if (!repliesContainer) {
              repliesContainer = document.createElement("div")
              repliesContainer.className = "comment-replies-container mt-3 ms-6 space-y-2 rounded-lg bg-white/60 border border-[#E3E3E3]/80 p-3"
              form?.parentNode?.insertBefore(repliesContainer, form)
            }
            repliesContainer.insertAdjacentHTML("beforeend", data.reply_html)
            const newRepliesCount = repliesContainer.children.length
            const viewRepliesLabel = parentCard.querySelector(".view-replies-label")
            if (viewRepliesLabel) {
              viewRepliesLabel.textContent = newRepliesCount === 1
                ? this.viewOneReplyValue
                : this.viewNRepliesValue.replace("%{count}", String(newRepliesCount))
            }
            this.bindDeleteButtons()
          }
        }
      } else if (data.comment_html && this.hasListTarget) {
        const list = this.listTarget
        const noComments = list.querySelector("p")
        if (noComments && list.children.length === 1) {
          noComments.remove()
        }
        list.insertAdjacentHTML("beforeend", data.comment_html)
        this.bindReplyButtons()
        this.bindDeleteButtons()
      }
    } else {
      const msg = data.message || "Failed to post comment"
      document.dispatchEvent(new CustomEvent("toast:show", { detail: { notificationHtml: `<div class="p-4 border-l-4 border-red-500 bg-white rounded shadow">${msg}</div>` }, bubbles: true }))
    }
  }

  bindReplyButtons() {
    this.element.querySelectorAll(".reply-to-comment").forEach(btn => {
      if (btn.dataset.bound) return
      btn.dataset.bound = "1"
      btn.addEventListener("click", () => {
        const form = this.element.querySelector(`.reply-form[data-reply-to="${btn.dataset.commentId}"]`)
        if (form) form.classList.toggle("hidden")
      })
    })
    this.element.querySelectorAll(".submit-reply").forEach(btn => {
      if (btn.dataset.bound) return
      btn.dataset.bound = "1"
      btn.addEventListener("click", () => {
        const parentId = btn.dataset.parentId
        const form = this.element.querySelector(`.reply-form[data-reply-to="${parentId}"]`)
        if (!form) return
        const ta = form.querySelector("textarea")
        const body = (ta?.value || "").trim()
        if (!body) return
        this.postComment(body, parentId)
      })
    })
    this.element.querySelectorAll(".cancel-reply").forEach(btn => {
      if (btn.dataset.bound) return
      btn.dataset.bound = "1"
      btn.addEventListener("click", () => {
        const form = btn.closest(".reply-form")
        if (form) {
          const ta = form.querySelector("textarea")
          if (ta) ta.value = ""
          form.classList.add("hidden")
        }
      })
    })
  }

  bindDeleteButtons() {
    this.element.querySelectorAll(".delete-comment").forEach(btn => {
      if (btn.dataset.deleteBound) return
      btn.dataset.deleteBound = "1"
      btn.addEventListener("click", (e) => {
        e.preventDefault()
        const commentId = btn.dataset.commentId
        const parentId = btn.dataset.parentId || ""
        const isReply = parentId !== ""
        this.openDeleteConfirm(commentId, parentId, isReply, btn)
      })
    })
  }

  openDeleteConfirm(commentId, parentId, isReply, triggerBtn) {
    this.pendingDelete = { commentId, parentId, isReply, triggerBtn }
    if (this.hasConfirmMessageTarget) {
      this.confirmMessageTarget.textContent = isReply ? this.confirmDeleteReplyValue : this.confirmDeleteCommentValue
    }
    if (this.hasConfirmDialogTarget) {
      this.confirmDialogTarget.showModal()
    }
  }

  cancelDelete() {
    this.pendingDelete = null
    if (this.hasConfirmDialogTarget) {
      this.confirmDialogTarget.close()
    }
  }

  confirmDelete() {
    if (!this.pendingDelete) return
    const { commentId, parentId, isReply, triggerBtn } = this.pendingDelete
    this.cancelDelete()
    this.deleteComment(commentId, parentId, isReply, triggerBtn)
  }

  async deleteComment(commentId, parentId, isReply, triggerBtn) {
    const url = `/dashboard/capa_management/${this.capaId}/capa_actions/${this.capaActionId}/comments/${commentId}`
    const opts = {
      method: "DELETE",
      headers: {
        "Accept": "application/json",
        "X-CSRF-Token": this.csrfToken
      }
    }
    const res = await fetch(url, opts)
    let data = {}
    try {
      const text = await res.text()
      if (text) data = JSON.parse(text)
    } catch (_) {}
    if (res.ok && data && data.success === true) {
      if (data.notification_html) {
        document.dispatchEvent(new CustomEvent("toast:show", { detail: { notificationHtml: data.notification_html }, bubbles: true }))
      }
      this.updateUIAfterDelete(commentId, parentId, isReply)
    } else {
      const msg = data.message || "Failed to delete comment"
      document.dispatchEvent(new CustomEvent("toast:show", { detail: { notificationHtml: `<div class="p-4 border-l-4 border-red-500 bg-white rounded shadow">${msg}</div>` }, bubbles: true }))
    }
  }

  updateUIAfterDelete(commentId, parentId, isReply) {
    const scope = document.getElementById("capa-action-comments-section") || this.element
    const listEl = scope.querySelector("[data-capa-action-comments-target='list']") || (this.hasListTarget ? this.listTarget : null)
    const id = String(commentId)
    const parentIdStr = String(parentId)

    if (isReply) {
      const row = scope.querySelector(`.comment-reply-row[data-comment-id="${id}"]`)
      if (row) row.remove()
      const parentCard = scope.querySelector(`[data-comment-id="${parentIdStr}"]`)
      if (parentCard && !parentCard.classList.contains("comment-reply-row")) {
        const repliesContainer = parentCard.querySelector(".comment-replies-container")
        if (repliesContainer) {
          const remaining = repliesContainer.querySelectorAll(".comment-reply-row").length
          const viewRepliesLabel = parentCard.querySelector(".view-replies-label")
          if (viewRepliesLabel) {
            viewRepliesLabel.textContent = remaining === 1
              ? this.viewOneReplyValue
              : this.viewNRepliesValue.replace("%{count}", String(remaining))
          }
          if (remaining === 0) {
            const details = parentCard.querySelector("details[data-comment-replies]")
            if (details) details.remove()
          }
        }
      }
    } else {
      const card = scope.querySelector(`[data-comment-id="${id}"]`)
      if (card && !card.classList.contains("comment-reply-row")) card.remove()
      if (listEl) {
        const commentCardsCount = Array.from(listEl.children).filter(el => el.getAttribute && el.getAttribute("data-comment-id")).length
        if (commentCardsCount === 0) {
          const existingEmpty = listEl.querySelector(".text-center.py-8")
          if (existingEmpty) existingEmpty.remove()
          const empty = document.createElement("div")
          empty.className = "text-center py-8 px-4 rounded-xl bg-[#F7F7FD] border border-[#E3E3E3]/60"
          const p = document.createElement("p")
          p.className = "text-sm text-[#797C81]"
          p.textContent = (scope.dataset && scope.dataset.noCommentsText) || this.element.dataset.noCommentsText || "No comments yet. Be the first to comment."
          empty.appendChild(p)
          listEl.appendChild(empty)
        }
      }
    }
  }
}
