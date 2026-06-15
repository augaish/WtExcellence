import { Controller } from "@hotwired/stimulus";
import Sortable from "sortablejs";

export default class extends Controller {
  static targets = ["clause"];
  static values = {
    pencilIconPath: String,
    deleteIconPath: String,
    discardModalTitle: String,
    discardModalMessage: String,
    discardModalConfirm: String,
    // i18n strings
    newClauseDefault: { type: String, default: "New Clause" },
    newCheckpointDefault: { type: String, default: "New checkpoint" },
    dropHere: { type: String, default: "Drop here" },
    dropHereRootLevel: { type: String, default: "Drop here · Root level" },
    dropHereInside: { type: String, default: "Drop here · inside %{code}" },
    dropHereToCancel: { type: String, default: "Drop here to cancel" },
    holdToNest: { type: String, default: "Hold to nest…" },
    dropToNest: { type: String, default: "Drop to nest" },
    addSubClauseLabel: { type: String, default: "Add Sub-clause" },
    addCheckpointLabel: { type: String, default: "Add Checkpoint" },
    editClauseLabel: { type: String, default: "Edit clause" },
    deleteClauseLabel: { type: String, default: "Delete clause" },
    deleteCheckpointLabel: { type: String, default: "Delete checkpoint" },
    editLabel: { type: String, default: "Edit" },
    deleteLabel: { type: String, default: "Delete" },
    confirmDeleteTitle: { type: String, default: "Confirm Delete" },
    confirmDeleteClauseMessage: { type: String, default: "Are you sure you want to delete this clause and all its sub-clauses and checkpoints?" },
    confirmDeleteCheckpointMessage: { type: String, default: "Are you sure you want to delete this checkpoint?" },
    dropCheckpointsHereLabel: { type: String, default: "Drop checkpoints here" },
    translatingLabel: { type: String, default: "Translating..." },
    markAsReviewedLabel: { type: String, default: "Mark as Reviewed" },
    saveLabel: { type: String, default: "Save" },
    cancelLabel: { type: String, default: "Cancel" },
    saveChangesLabel: { type: String, default: "Save Changes" }
  };

  // ============================================
  // Lifecycle Methods
  // ============================================

  connect() {
    document.addEventListener("click", this.handleClickOutside.bind(this));
    window.addEventListener("beforeunload", this.boundBeforeUnload = this.handleBeforeUnload.bind(this));

    // Pending changes state (no DB writes until Save all)
    this.resetPendingState();

    // Create cancel drop zone
    this.createCancelDropZone();

    // Initialize drag-and-drop after a small delay to ensure DOM is ready
    setTimeout(() => {
      this.initializeDragAndDrop();
    }, 100);
  }

  disconnect() {
    document.removeEventListener("click", this.handleClickOutside.bind(this));
    if (this.boundBeforeUnload) {
      window.removeEventListener("beforeunload", this.boundBeforeUnload);
    }
    if (this.boundHandleDragOverCancel) {
      document.removeEventListener("dragover", this.boundHandleDragOverCancel);
      document.removeEventListener("pointermove", this.boundHandleDragOverCancel);
    }
    // Destroy all Sortable instances
    if (this.sortableInstances) {
      this.sortableInstances.forEach((instance) => instance.destroy());
    }
    // Remove cancel drop zone
    if (this.cancelDropZone) {
      this.cancelDropZone.remove();
    }
  }

  // ============================================
  // Pending changes state
  // ============================================

  resetPendingState() {
    this.pending = {
      clauses: { created: [], updated: {}, moved: [], reordered: [], deleted: [] },
      checkpoints: { created: [], updated: {}, moved: [], reordered: [], deleted: [] }
    };
    this.tempIdToRealId = {}; // clause and checkpoint temp id -> real id after save
    this.updateDirtyIndicator();
  }

  hasPendingChanges() {
    const p = this.pending;
    return (
      p.clauses.created.length > 0 ||
      Object.keys(p.clauses.updated).length > 0 ||
      p.clauses.moved.length > 0 ||
      p.clauses.reordered.length > 0 ||
      p.clauses.deleted.length > 0 ||
      p.checkpoints.created.length > 0 ||
      Object.keys(p.checkpoints.updated).length > 0 ||
      p.checkpoints.moved.length > 0 ||
      p.checkpoints.reordered.length > 0 ||
      p.checkpoints.deleted.length > 0
    );
  }

  updateDirtyIndicator() {
    const indicator = document.getElementById("clause-editor-unsaved-indicator");
    const saveBtn = document.getElementById("clause-editor-save-all-btn");
    const discardBtn = document.getElementById("clause-editor-discard-btn");
    const isDirty = this.hasPendingChanges();
    if (indicator) {
      indicator.classList.toggle("hidden", !isDirty);
    }
    if (saveBtn) {
      saveBtn.disabled = !isDirty;
    }
    if (discardBtn) {
      discardBtn.disabled = !isDirty;
    }
  }

  handleBeforeUnload(e) {
    if (this.isDiscarding) return;
    if (this.hasPendingChanges()) {
      e.preventDefault();
    }
  }

  async saveAllChanges(event) {
    if (event) event.preventDefault();
    if (!this.hasPendingChanges()) return;

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content;
    const headers = {
      "Content-Type": "application/json",
      "X-CSRF-Token": csrf
    };
    const tempIdToRealId = { ...this.tempIdToRealId };

    try {
      // 1) Delete clauses
      for (const clauseId of this.pending.clauses.deleted) {
        const res = await fetch(`/clauses/${clauseId}`, { method: "DELETE", headers });
        if (!res.ok) {
          const err = await res.json().catch(() => ({}));
          throw new Error(err.error || `Failed to delete clause ${clauseId}`);
        }
      }

      // 2) Delete checkpoints
      for (const checkpointId of this.pending.checkpoints.deleted) {
        const res = await fetch(`/checkpoints/${checkpointId}`, { method: "DELETE", headers });
        if (!res.ok) {
          const err = await res.json().catch(() => ({}));
          throw new Error(err.error || `Failed to delete checkpoint ${checkpointId}`);
        }
      }

      // 3) Create clauses (parent before child; resolve temp parent ids)
      const createdClauses = [...this.pending.clauses.created];
      while (createdClauses.length > 0) {
        let progress = false;
        for (let i = createdClauses.length - 1; i >= 0; i--) {
          const c = createdClauses[i];
          const parentRealId = c.parentId == null
            ? null
            : (tempIdToRealId[c.parentId] ?? (String(c.parentId).startsWith("tmp_") ? null : c.parentId));
          if (c.parentId != null && String(c.parentId).startsWith("tmp_") && parentRealId == null) continue;
          const body = c.standardVersionId
            ? { standard_version_id: c.standardVersionId, title: c.title || this.newClauseDefaultValue }
            : { parent_id: parentRealId, title: c.title || this.newClauseDefaultValue };
          const res = await fetch("/clauses", { method: "POST", headers, body: JSON.stringify(body) });
          if (!res.ok) {
            const err = await res.json().catch(() => ({}));
            throw new Error(err.error || "Failed to create clause");
          }
          const data = await res.json();
          tempIdToRealId[c.tempId] = data.clause_id;
          createdClauses.splice(i, 1);
          progress = true;
        }
        if (!progress && createdClauses.length > 0) throw new Error("Could not create clauses: check parent order");
      }

      // 4) Create checkpoints (use real clause ids)
      for (const cp of this.pending.checkpoints.created) {
        const clauseId = tempIdToRealId[cp.clauseId] ?? cp.clauseId;
        const res = await fetch("/checkpoints", {
          method: "POST",
          headers,
          body: JSON.stringify({ clause_id: clauseId, text: cp.text ?? "" })
        });
        if (!res.ok) {
          const err = await res.json().catch(() => ({}));
          throw new Error(err.error || "Failed to create checkpoint");
        }
        const data = await res.json();
        if (data.checkpoint?.id) tempIdToRealId[cp.tempId] = data.checkpoint.id;
      }

      // 5) Update clauses (backend only accepts title/summary/body, not code)
      for (const [id, payload] of Object.entries(this.pending.clauses.updated)) {
        if (String(id).startsWith("tmp_")) continue;
        const res = await fetch(`/clauses/${id}`, {
          method: "PATCH",
          headers,
          body: JSON.stringify({ title: payload.title })
        });
        if (!res.ok) {
          const err = await res.json().catch(() => ({}));
          throw new Error(err.error || `Failed to update clause ${id}`);
        }
      }

      // 6) Move clauses
      for (const { clauseId, newParentId } of this.pending.clauses.moved) {
        const res = await fetch(`/clauses/${clauseId}/move`, {
          method: "PATCH",
          headers,
          body: JSON.stringify({ new_parent_id: newParentId })
        });
        if (!res.ok) {
          const err = await res.json().catch(() => ({}));
          throw new Error(err.error || `Failed to move clause ${clauseId}`);
        }
      }

      // 7) Reorder clauses
      for (const { clauseId, targetClauseId, position } of this.pending.clauses.reordered) {
        const res = await fetch(`/clauses/${clauseId}/reorder`, {
          method: "PATCH",
          headers,
          body: JSON.stringify({ target_clause_id: targetClauseId, position: position || "after" })
        });
        if (!res.ok) {
          const err = await res.json().catch(() => ({}));
          throw new Error(err.error || `Failed to reorder clause ${clauseId}`);
        }
      }

      // 8) Update checkpoints
      for (const [id, payload] of Object.entries(this.pending.checkpoints.updated)) {
        const res = await fetch(`/checkpoints/${id}`, {
          method: "PATCH",
          headers,
          body: JSON.stringify({ text: payload.text })
        });
        if (!res.ok) {
          const err = await res.json().catch(() => ({}));
          throw new Error(err.error || `Failed to update checkpoint ${id}`);
        }
      }

      // 9) Move checkpoints
      for (const { checkpointId, newClauseId } of this.pending.checkpoints.moved) {
        const clauseId = tempIdToRealId[newClauseId] ?? newClauseId;
        const res = await fetch(`/checkpoints/${checkpointId}/move`, {
          method: "PATCH",
          headers,
          body: JSON.stringify({ target_clause_id: clauseId })
        });
        if (!res.ok) {
          const err = await res.json().catch(() => ({}));
          throw new Error(err.error || `Failed to move checkpoint ${checkpointId}`);
        }
      }

      // 10) Reorder checkpoints
      for (const { checkpointId, targetCheckpointId } of this.pending.checkpoints.reordered) {
        const res = await fetch(`/checkpoints/${checkpointId}/move`, {
          method: "PATCH",
          headers,
          body: JSON.stringify({ target_checkpoint_id: targetCheckpointId })
        });
        if (!res.ok) {
          const err = await res.json().catch(() => ({}));
          throw new Error(err.error || `Failed to reorder checkpoint ${checkpointId}`);
        }
      }

      this.resetPendingState();
      // Reload so DOM matches server (codes, IDs for new items, etc.)
      window.location.reload();
    } catch (err) {
      console.error("saveAllChanges error:", err);
      alert(err.message || "Failed to save changes. Please try again.");
    }
  }

  async discardChanges(event) {
    if (event) event.preventDefault();
    if (!this.hasPendingChanges()) return;
    if (typeof window.showConfirmationModal !== "function") {
      await import("helpers/confirmation_modal");
    }
    const title = this.discardModalTitleValue || "Discard changes";
    const message = this.discardModalMessageValue || "Discard all unsaved changes? This cannot be undone.";
    const confirmText = this.discardModalConfirmValue || "Discard";
    const confirmed = await window.showConfirmationModal(message, {
      title,
      confirmText,
      buttonStyle: "danger"
    });
    if (!confirmed) return;
    this.isDiscarding = true;
    window.location.reload();
  }

  // ============================================
  // Drag-and-Drop Methods
  // ============================================

  createCancelDropZone() {
    // Create the cancel drop zone element
    const cancelZone = document.createElement("div");
    cancelZone.id = "cancel-drop-zone";
    cancelZone.className =
      "fixed bottom-6 left-6 bg-[#D9CAEF] text-white px-6 py-4 rounded-lg shadow-2xl flex items-center gap-3 transition-all duration-200 opacity-0 pointer-events-none z-50";
    const cancelLabel = document.createElement("span");
    cancelLabel.className = "font-medium";
    cancelLabel.textContent = this.dropHereToCancelValue;
    cancelZone.innerHTML = `
      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
      </svg>
    `;
    cancelZone.appendChild(cancelLabel);

    document.body.appendChild(cancelZone);
    this.cancelDropZone = cancelZone;
    this.isDraggingOverCancel = false;

    // Track mouse position during drag. We listen to both: `dragover` covers
    // native HTML5 drag (used by the checkpoint sortable), `pointermove`
    // covers SortableJS fallback mode (used by the clause sortable so that
    // auto-scroll works reliably).
    this.boundHandleDragOverCancel = this.handleDragOverCancel.bind(this);
    document.addEventListener("dragover", this.boundHandleDragOverCancel);
    document.addEventListener("pointermove", this.boundHandleDragOverCancel);
  }

  handleDragOverCancel(event) {
    if (!this.cancelDropZone || !this.isDragging) return;

    const rect = this.cancelDropZone.getBoundingClientRect();
    const mouseX = event.clientX;
    const mouseY = event.clientY;

    // Check if mouse is over cancel zone
    const isOver =
      mouseX >= rect.left &&
      mouseX <= rect.right &&
      mouseY >= rect.top &&
      mouseY <= rect.bottom;

    if (isOver !== this.isDraggingOverCancel) {
      this.isDraggingOverCancel = isOver;
      if (isOver) {
        this.cancelDropZone.classList.add("scale-110", "bg-[#D9CAEF]");
      } else {
        this.cancelDropZone.classList.remove("scale-110", "bg-[#D9CAEF]");
      }
    }
  }

  showCancelDropZone() {
    if (this.cancelDropZone) {
      this.isDragging = true;
      this.cancelDropZone.classList.remove("opacity-0", "pointer-events-none");
      this.cancelDropZone.classList.add("opacity-100");
    }
  }

  hideCancelDropZone() {
    if (this.cancelDropZone) {
      this.isDragging = false;
      this.isDraggingOverCancel = false;
      this.cancelDropZone.classList.add("opacity-0", "pointer-events-none");
      this.cancelDropZone.classList.remove(
        "opacity-100",
        "scale-110",
        "bg-red-600"
      );
    }
  }

  initializeDragAndDrop() {
    this.sortableInstances = [];

    // Initialize drag-and-drop for all clause containers
    this.initializeClauseSortables();

    // Initialize drag-and-drop for all checkpoint containers
    this.initializeCheckpointSortables();
  }

  getClauseSortableConfig() {
    return {
      group: {
        name: "clauses",
        pull: true,
        put: true,
      },
      animation: 150,
      handle: "[data-drag-handle]",
      draggable: ".clause-hierarchy",
      ghostClass: "sortable-ghost",
      chosenClass: "sortable-chosen",
      dragClass: "sortable-drag",
      forceFallback: true,
      fallbackOnBody: true,
      fallbackTolerance: 5,
      swapThreshold: 0.3,
      direction: "vertical",
      emptyInsertThreshold: 25,
      scroll: true,
      forceAutoScrollFallback: true,
      scrollSensitivity: 80,
      scrollSpeed: 20,
      bubbleScroll: true,
      onStart: (evt) => {
        this.nestingUnlockedContainers = new WeakSet();
        this.clearNestingHover();
        this.clearFreeDropTarget();
        this.dragSourceContainer = evt.from;
        if (evt.from) evt.from.classList.add("drag-source-container");
        document.body.classList.add("dragging-clause");
        this.showCancelDropZone();
      },
      onEnd: (evt) => {
        this.clearNestingHover();
        this.clearAllNestingClasses();
        this.clearFreeDropTarget();
        document.body.classList.remove("dragging-clause");
        this.element
          .querySelectorAll(".drag-source-container")
          .forEach((el) => el.classList.remove("drag-source-container"));
        this.dragSourceContainer = null;
        this.hideCancelDropZone();

        if (this.isDraggingOverCancel) {
          this.revertDrag(evt);
          return;
        }

        const clauseId = evt.item.dataset.clauseId;
        const fromContainer = evt.from;
        const toContainer = evt.to;

        if (fromContainer === toContainer) {
          this.recordClauseReorder(evt);
        } else {
          this.recordClauseMove(evt);
        }
      },
      onMove: (evt) => {
        const draggedElement = evt.dragged;
        const relatedElement = evt.related;

        // Prevent dropping a clause into itself or one of its own descendants
        // (would create a cycle). It is fine for the related sibling to be an
        // ancestor of the dragged element — that is the un-nesting case.
        if (
          relatedElement &&
          (relatedElement === draggedElement ||
            draggedElement.contains(relatedElement))
        ) {
          return false;
        }

        // Keep the source-container class on the container the item is
        // currently in (it can change if cross-container moves succeed).
        if (this.dragSourceContainer !== evt.from) {
          if (this.dragSourceContainer) {
            this.dragSourceContainer.classList.remove("drag-source-container");
          }
          if (evt.from) {
            evt.from.classList.add("drag-source-container");
          }
          this.dragSourceContainer = evt.from;
        }

        // Same-container moves (reorder at the same level) are always free.
        if (evt.to === evt.from) {
          this.clearNestingHover();
          this.clearFreeDropTarget();
          return true;
        }

        // Moving up (un-nesting) or sideways at the same depth is free.
        // Only deepening into a new subtree requires a 1s hold.
        if (this.containerDepth(evt.to) <= this.containerDepth(evt.from)) {
          this.clearNestingHover();
          this.setFreeDropTarget(evt.to);
          return true;
        }

        this.clearFreeDropTarget();
        if (this.nestingUnlockedContainers && this.nestingUnlockedContainers.has(evt.to)) {
          return true;
        }

        this.startNestingHoverTimer(evt.to);
        return false;
      },
    };
  }

  // ============================================
  // Nesting hold-to-confirm helpers
  // ============================================

  escapeHtml(str) {
    return String(str ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  escapeAttr(str) {
    return String(str ?? "")
      .replace(/&/g, "&amp;")
      .replace(/"/g, "&quot;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  containerDepth(container) {
    if (!container) return 0;
    let depth = 0;
    let el = container.parentElement;
    while (el) {
      if (el.classList && el.classList.contains("clause-hierarchy")) depth++;
      el = el.parentElement;
    }
    return depth;
  }

  startNestingHoverTimer(container) {
    if (!container) return;
    if (this.nestingHoverContainer === container) return;

    this.clearNestingHover();
    this.nestingHoverContainer = container;
    container.dataset.holdLabel = this.holdToNestValue;
    container.classList.add("nesting-hold-pending");

    this.nestingHoverTimer = setTimeout(() => {
      if (!this.nestingUnlockedContainers) {
        this.nestingUnlockedContainers = new WeakSet();
      }
      this.nestingUnlockedContainers.add(container);
      container.classList.remove("nesting-hold-pending");
      delete container.dataset.holdLabel;
      container.dataset.readyLabel = this.dropToNestValue;
      container.classList.add("nesting-hold-ready");
      this.nestingHoverTimer = null;
    }, 1000);
  }

  clearNestingHover() {
    if (this.nestingHoverTimer) {
      clearTimeout(this.nestingHoverTimer);
      this.nestingHoverTimer = null;
    }
    if (this.nestingHoverContainer) {
      this.nestingHoverContainer.classList.remove("nesting-hold-pending");
      delete this.nestingHoverContainer.dataset.holdLabel;
      this.nestingHoverContainer = null;
    }
  }

  clearAllNestingClasses() {
    this.element
      .querySelectorAll(".nesting-hold-pending, .nesting-hold-ready")
      .forEach((el) => {
        el.classList.remove("nesting-hold-pending", "nesting-hold-ready");
        delete el.dataset.holdLabel;
        delete el.dataset.readyLabel;
      });
  }

  setFreeDropTarget(container) {
    if (!container || this.freeDropTarget === container) return;
    this.clearFreeDropTarget();
    container.classList.add("drop-target-free");
    container.dataset.dropLabel = this.dropTargetLabel(container);
    this.freeDropTarget = container;
  }

  clearFreeDropTarget() {
    if (this.freeDropTarget) {
      this.freeDropTarget.classList.remove("drop-target-free");
      delete this.freeDropTarget.dataset.dropLabel;
      this.freeDropTarget = null;
    }
    this.element
      .querySelectorAll(".drop-target-free")
      .forEach((el) => {
        el.classList.remove("drop-target-free");
        delete el.dataset.dropLabel;
      });
  }

  dropTargetLabel(container) {
    if (container.id === "root-clauses-container") return this.dropHereRootLevelValue;
    const parentClause = container.closest(".clause-hierarchy");
    if (!parentClause) return this.dropHereValue;
    const codeInput = parentClause.querySelector('input[type="text"]');
    const code = codeInput?.value?.trim();
    return code
      ? this.dropHereInsideValue.replace("%{code}", code)
      : this.dropHereValue;
  }

  initializeClauseSortables() {
    const containers = [];

    const rootContainer = this.element.querySelector("#root-clauses-container");
    if (rootContainer) {
      containers.push(rootContainer);
    }

    const nestedContainers = this.element.querySelectorAll(
      "[data-children-container]"
    );
    containers.push(...nestedContainers);

    containers.forEach((container) => {
      if (container.dataset.sortableInitialized === "true") return;

      const sortable = Sortable.create(container, this.getClauseSortableConfig());

      container.dataset.sortableInitialized = "true";
      this.sortableInstances.push(sortable);
    });
  }

  initializeCheckpointSortables() {
    const checkpointContainers = document.querySelectorAll(
      "[data-checkpoints-list]"
    );

    checkpointContainers.forEach((container) => {
      // Skip if already initialized
      if (container.dataset.sortableInitialized === "true") return;

      const sortable = Sortable.create(container, {
        group: "checkpoints",
        animation: 250,
        handle: "[data-drag-handle]",
        draggable: "[data-checkpoint-id]",
        ghostClass: "sortable-ghost",
        chosenClass: "sortable-chosen-checkpoint",
        dragClass: "sortable-drag",
        filter: ".text-sm.text-gray-600, .empty-checkpoint-hint", // Ignore "Checkpoints:" label and empty hint

        // Smooth auto-scrolling
        scroll: window, // Scroll the window
        forceAutoScrollFallback: true, // Force auto-scroll even when native drag is detected
        scrollSensitivity: 50, // Distance from edge to start scrolling (px) - very close to edges
        scrollSpeed: 15, // Scroll speed (px per frame) - moderate speed
        bubbleScroll: true, // Enable scrolling in parent containers

        onStart: (evt) => {
          // Add class to body when dragging checkpoint
          document.body.classList.add("dragging-checkpoint");
          // Show cancel drop zone
          this.showCancelDropZone();
        },

        onMove: (evt) => {
          // Only allow dropping into valid checkpoint containers
          // Prevent dropping directly on clause divs or other invalid elements
          const relatedElement = evt.related;
          const draggedElement = evt.dragged;
          
          // Prevent dropping on itself or its descendants
          if (relatedElement.contains(draggedElement)) {
            return false;
          }
          
          // Ensure the drop target is a valid checkpoint container
          // The related element should be within a [data-checkpoints-list] container
          const isValidDropTarget = relatedElement.closest("[data-checkpoints-list]") !== null;
          
          if (!isValidDropTarget) {
            return false;
          }
          
          return true;
        },

        onEnd: (evt) => {
          document.body.classList.remove("dragging-checkpoint");
          this.hideCancelDropZone();

          if (this.isDraggingOverCancel) {
            this.revertDrag(evt);
            return;
          }
          const fromContainer = evt.from;
          const toContainer = evt.to;

          if (fromContainer === toContainer) {
            this.recordCheckpointReorder(evt);
          } else {
            this.recordCheckpointMove(evt);
          }

          this.cleanupEmptyCheckpointContainer(
            fromContainer.closest("[data-checkpoints-container]")
          );
        },
      });

      container.dataset.sortableInitialized = "true";
      this.sortableInstances.push(sortable);
    });
  }

  recordClauseReorder(evt) {
    const siblings = Array.from(evt.to.children).filter((el) =>
      el.classList.contains("clause-hierarchy")
    );
    const newIndex = siblings.indexOf(evt.item);
    const useAfter = newIndex > 0;
    const targetClause = useAfter ? siblings[newIndex - 1] : siblings[newIndex + 1];
    if (!targetClause) return;
    const clauseId = evt.item.dataset.clauseId;
    const targetId = targetClause.dataset.clauseId;
    const position = useAfter ? "after" : "before";
    this.pending.clauses.reordered.push({ clauseId, targetClauseId: targetId, position });
    this.updateDirtyIndicator();
  }

  recordClauseMove(evt) {
    const newParentContainer = evt.to;
    const newParentClause = newParentContainer.closest(".clause-hierarchy");
    const newParentId = newParentClause?.dataset.clauseId ?? null;
    const clauseId = evt.item.dataset.clauseId;
    this.pending.clauses.moved.push({ clauseId, newParentId });
    this.updateDirtyIndicator();
  }

  async handleClauseReorder(evt) {
    const clauseId = evt.item.dataset.clauseId;

    // Find the target clause (the one after which we dropped)
    const siblings = Array.from(evt.to.children).filter((el) =>
      el.classList.contains("clause-hierarchy")
    );
    const newIndex = siblings.indexOf(evt.item);
    const targetClause =
      newIndex > 0 ? siblings[newIndex - 1] : siblings[newIndex + 1];

    if (!targetClause) return;

    const targetId = targetClause.dataset.clauseId;

    try {
      const response = await fetch(`/clauses/${clauseId}/reorder`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')
            .content,
        },
        body: JSON.stringify({
          target_clause_id: targetId,
        }),
      });

      if (response.ok) {
        const data = await response.json();

        // Update codes for all affected clauses
        if (data.updated_codes) {
          Object.entries(data.updated_codes).forEach(([id, newCode]) => {
            // Convert ID to string to match data attribute
            const clauseDiv = document.querySelector(
              `[data-clause-id="${id}"]`
            );
            if (clauseDiv) {
              // Update the code input (first input in the clause)
              const allInputs = clauseDiv.querySelectorAll('input[type="text"]');
              const codeInput = allInputs.length > 0 ? allInputs[0] : null;
              if (codeInput) {
                codeInput.value = newCode;
                // Trigger input event to ensure any listeners are notified
                codeInput.dispatchEvent(new Event('input', { bubbles: true }));
              } else {
                console.warn(`Could not find code input for clause ${id}`);
              }
            } else {
              console.warn(`Could not find clause div with data-clause-id="${id}"`);
            }
          });
        }
      } else {
        const error = await response.json();
        alert(`Failed to reorder clause: ${error.error || "Unknown error"}`);
        this.revertDrag(evt);
      }
    } catch (error) {
      console.error("Error reordering clause:", error);
      alert("An error occurred while reordering the clause. Please try again.");
      this.revertDrag(evt);
    }
  }

  async handleClauseMove(evt) {
    const clauseId = evt.item.dataset.clauseId;

    // Find the new parent by looking at the container
    const newParentContainer = evt.to;
    const newParentClause = newParentContainer.closest(".clause-hierarchy");
    const newParentId = newParentClause?.dataset.clauseId;

    // If no parent found, it means it's being moved to root level
    try {
      const response = await fetch(`/clauses/${clauseId}/move`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')
            .content,
        },
        body: JSON.stringify({
          new_parent_id: newParentId, // Can be null for root level
        }),
      });

      if (response.ok) {
        const data = await response.json();

        // Update the moved clause code
        const allInputs = evt.item.querySelectorAll('input[type="text"]');
        const codeInput = allInputs.length > 0 ? allInputs[0] : null;
        if (codeInput) {
          codeInput.value = data.new_code;
        }

        // Update ALL affected clause codes (including old siblings that need renumbering)
        if (data.updated_codes) {
          Object.entries(data.updated_codes).forEach(([id, newCode]) => {
            // Search globally, not just within moved clause
            const clauseDiv = document.querySelector(
              `[data-clause-id="${id}"]`
            );
            if (clauseDiv) {
              // Update the code input (first input in the clause)
              const clauseInputs = clauseDiv.querySelectorAll('input[type="text"]');
              const clauseCodeInput = clauseInputs.length > 0 ? clauseInputs[0] : null;
              if (clauseCodeInput) {
                clauseCodeInput.value = newCode;
              }
            }
          });
        }
      } else {
        const error = await response.json();
        alert(`Failed to move clause: ${error.error || "Unknown error"}`);
        this.revertDrag(evt);
      }
    } catch (error) {
      console.error("Error moving clause:", error);
      alert("An error occurred while moving the clause. Please try again.");
      this.revertDrag(evt);
    }
  }

  recordCheckpointReorder(evt) {
    const siblings = Array.from(evt.to.children).filter((el) => el.dataset.checkpointId);
    const newIndex = siblings.indexOf(evt.item);
    const targetCheckpoint = newIndex > 0 ? siblings[newIndex - 1] : siblings[newIndex + 1];
    if (!targetCheckpoint) return;
    const checkpointId = evt.item.dataset.checkpointId;
    const targetId = targetCheckpoint.dataset.checkpointId;
    if (targetId?.startsWith("tmp_")) return;
    this.pending.checkpoints.reordered.push({ checkpointId, targetCheckpointId: targetId });
    this.updateDirtyIndicator();
  }

  recordCheckpointMove(evt) {
    const checkpointId = evt.item.dataset.checkpointId;
    if (checkpointId.startsWith("tmp_")) {
      this.revertDrag(evt);
      return;
    }
    const newClauseContainer = evt.to.closest("[data-checkpoints-container]");
    const parentClause = newClauseContainer?.closest(".clause-hierarchy");
    const newClauseId = parentClause?.dataset.clauseId;
    if (!newClauseId) return;
    this.pending.checkpoints.moved.push({ checkpointId, newClauseId });
    this.updateDirtyIndicator();
  }

  async handleCheckpointReorder(evt) {
    const checkpointId = evt.item.dataset.checkpointId;

    // Skip for temporary checkpoints
    if (checkpointId.startsWith("tmp_")) {
      return;
    }

    // Find the target checkpoint (the one after which we dropped)
    const siblings = Array.from(evt.to.children).filter(
      (el) => el.dataset.checkpointId
    );
    const newIndex = siblings.indexOf(evt.item);
    const targetCheckpoint =
      newIndex > 0 ? siblings[newIndex - 1] : siblings[newIndex + 1];

    if (!targetCheckpoint) return;

    const targetId = targetCheckpoint.dataset.checkpointId;
    if (targetId.startsWith("tmp_")) return;

    try {
      const response = await fetch(`/checkpoints/${checkpointId}/move`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')
            .content,
        },
        body: JSON.stringify({
          target_checkpoint_id: targetId,
        }),
      });

      if (!response.ok) {
        const error = await response.json();
        alert(
          `Failed to reorder checkpoint: ${error.error || "Unknown error"}`
        );
        this.revertDrag(evt);
      }
    } catch (error) {
      console.error("Error reordering checkpoint:", error);
      alert(
        "An error occurred while reordering the checkpoint. Please try again."
      );
      this.revertDrag(evt);
    }
  }

  async handleCheckpointMove(evt) {
    const checkpointId = evt.item.dataset.checkpointId;

    // Skip for temporary checkpoints
    if (checkpointId.startsWith("tmp_")) {
      alert("Cannot move unsaved checkpoints to a different clause");
      this.revertDrag(evt);
      return;
    }

    const newClauseContainer = evt.to.closest("[data-checkpoints-container]");
    const parentClauseElement =
      newClauseContainer?.closest(".clause-hierarchy");
    const clauseId = parentClauseElement?.dataset.clauseId;

    if (!clauseId) {
      alert("Cannot determine target clause");
      this.revertDrag(evt);
      return;
    }

    try {
      const response = await fetch(`/checkpoints/${checkpointId}/move`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')
            .content,
        },
        body: JSON.stringify({
          target_clause_id: clauseId,
        }),
      });

      if (!response.ok) {
        const error = await response.json();
        alert(`Failed to move checkpoint: ${error.error || "Unknown error"}`);
        this.revertDrag(evt);
      }
    } catch (error) {
      console.error("Error moving checkpoint:", error);
      alert("An error occurred while moving the checkpoint. Please try again.");
      this.revertDrag(evt);
    }
  }

  cleanupEmptyCheckpointContainer(checkpointsContainer) {
    if (!checkpointsContainer) return;

    const checkpointsListContainer = checkpointsContainer.querySelector(
      "[data-checkpoints-list]"
    );
    if (!checkpointsListContainer) return;

    const checkpoints = checkpointsListContainer.querySelectorAll(
      "[data-checkpoint-id]"
    );
    const checkpointsLabel = checkpointsListContainer.querySelector(
      "[data-checkpoints-label]"
    );
    const emptyHint =
      checkpointsListContainer.querySelector("[data-empty-hint]");

    if (checkpoints.length === 0) {
      if (checkpointsLabel) {
        checkpointsLabel.style.display = "none";
      }

      if (emptyHint) {
        emptyHint.style.display = "block";
      } else {
        const newHint = document.createElement("div");
        newHint.setAttribute("data-empty-hint", "");
        newHint.className =
          "empty-checkpoint-hint text-xs text-gray-400 text-center py-4 border-2 border-dashed border-transparent rounded-lg";
        newHint.textContent = this.dropCheckpointsHereLabelValue;
        checkpointsListContainer.appendChild(newHint);
      }
    } else {
      if (checkpointsLabel) {
        checkpointsLabel.style.display = "block";
      }

      if (emptyHint) {
        emptyHint.style.display = "none";
      }
    }
  }

  revertDrag(evt) {
    evt.from.insertBefore(evt.item, evt.from.children[evt.oldIndex]);
  }

  getClauseHTML(tempId, parentId, level, title, code) {
    const levelNum = level ?? 0;
    const titleVal = title || this.newClauseDefaultValue;
    const codeVal = code || "?";
    const pencilPath = this.pencilIconPathValue || "/assets/pencil-icon.svg";
    const deletePath = this.deleteIconPathValue || "/assets/delete-clause-icon.svg";
    const editClauseLabel = this.escapeAttr(this.editClauseLabelValue);
    const deleteClauseLabel = this.escapeAttr(this.deleteClauseLabelValue);
    const editAlt = this.escapeAttr(this.editLabelValue);
    const deleteAlt = this.escapeAttr(this.deleteLabelValue);
    const addSubClauseText = this.escapeHtml(this.addSubClauseLabelValue);
    const addCheckpointText = this.escapeHtml(this.addCheckpointLabelValue);
    const dropCheckpointsText = this.escapeHtml(this.dropCheckpointsHereLabelValue);
    const addSubClauseClass = levelNum === 0
      ? "px-3 sm:px-4 py-2 min-h-[44px] text-xs sm:text-sm font-medium flex items-center gap-2 bg-[#D6C4ED] text-[#0D1120] rounded-xl hover:opacity-90"
      : "px-3 sm:px-4 py-2 min-h-[44px] text-xs sm:text-sm font-medium flex items-center gap-2 bg-[#FFFFFF] text-[#5C3984] border border-gray-400 rounded-xl hover:bg-gray-50";
    return `
<div class="clause-hierarchy bg-white border border-gray-200 rounded-lg p-3 sm:p-4 mb-8 sm:mb-14 mt-8 sm:mt-14" data-clause-id="${tempId}" data-level="${levelNum}">
  <div>
    <div class="flex flex-col sm:flex-row sm:justify-between sm:items-center gap-3">
      <div class="flex items-center space-x-2 sm:space-x-3 flex-1 min-w-0">
        <div data-drag-handle class="cursor-move p-2 hover:bg-gray-50 rounded flex-shrink-0 min-w-[44px] min-h-[44px] flex items-center justify-center">
          <div class="grid grid-cols-3 gap-1 w-5">
            <div class="w-1 h-1 bg-[#5C3984] rounded-full"></div>
            <div class="w-1 h-1 bg-[#5C3984] rounded-full"></div>
            <div class="w-1 h-1 bg-[#5C3984] rounded-full"></div>
            <div class="w-1 h-1 bg-[#5C3984] rounded-full"></div>
            <div class="w-1 h-1 bg-[#5C3984] rounded-full"></div>
            <div class="w-1 h-1 bg-[#5C3984] rounded-full"></div>
          </div>
        </div>
        <input type="text" value="${codeVal}" readonly class="text-xs sm:text-sm font-semibold text-[#5C3984] w-16 sm:w-20 border-none bg-transparent focus:outline-none rounded px-2 py-1 flex-shrink-0">
        <input type="text" value="${titleVal}" readonly class="flex-1 text-xs sm:text-sm text-[#0D1120] border-none bg-transparent focus:outline-none rounded px-2 py-1 min-w-0 break-words">
      </div>
      <div class="flex flex-wrap items-center gap-2 sm:space-x-2">
        <button class="p-2 min-w-[44px] min-h-[44px] flex items-center justify-center text-gray-600 hover:bg-gray-100 rounded transition-colors" data-action="click->clause-editor#toggleEdit" title="${editClauseLabel}">
          <img src="${pencilPath}" class="w-4 h-4 max-w-full h-auto" alt="${editAlt}">
        </button>
        <button class="p-2 min-w-[44px] min-h-[44px] flex items-center justify-center text-gray-600 hover:text-red-600 transition-colors" data-action="click->clause-editor#deleteClause" title="${deleteClauseLabel}">
          <img src="${deletePath}" class="w-4 h-4 max-w-full h-auto" alt="${deleteAlt}">
        </button>
        <button class="${addSubClauseClass}" data-action="click->clause-editor#addClause">
          <span class="whitespace-nowrap">${addSubClauseText}</span>
        </button>
        <button class="px-3 sm:px-4 py-2 min-h-[44px] text-xs sm:text-sm font-medium flex items-center gap-2 bg-[#FFFFFF] text-[#5C3984] border border-gray-400 rounded-xl hover:bg-gray-50" data-action="click->clause-editor#addCheckpoint">
          <span class="whitespace-nowrap">${addCheckpointText}</span>
        </button>
      </div>
    </div>
  </div>
  <div class="mt-4 mb-4 pl-4 sm:pl-8 checkpoint-drop-zone" data-checkpoints-container data-clause-id="${tempId}">
    <div data-checkpoints-list class="space-y-2 mb-4">
      <div data-empty-hint class="empty-checkpoint-hint text-xs text-gray-400 text-center py-4 border-2 border-dashed border-transparent rounded-lg">${dropCheckpointsText}</div>
    </div>
  </div>
  <div data-children-container class="mt-4 space-y-3 min-h-[20px]"></div>
</div>`;
  }

  // Helper method to show confirmation modal
  async showConfirmation(message, options = {}) {
    // Try to load the helper dynamically if not already available
    if (typeof window.showConfirmationModal !== 'function') {
      try {
        await import("helpers/confirmation_modal");
      } catch (_error) {}
    }
    
    // Use the global helper if available, otherwise fallback to confirm
    if (typeof window.showConfirmationModal === 'function') {
      return await window.showConfirmationModal(message, options);
    }
    // Fallback to browser confirm
    return confirm(message);
  }

  // ============================================
  // Edit Mode Methods
  // ============================================

  handleClickOutside(event) {
    if (
      !event.target.closest(".clause-hierarchy") &&
      !event.target.closest("button[data-action*='toggleEdit']") &&
      !event.target.closest("button[data-action*='saveClause']") &&
      !event.target.closest("button[data-action*='cancelEditClause']")
    ) {
      document.querySelectorAll(".editing-mode").forEach((clause) => {
        const isCheckpoint = clause.hasAttribute("data-checkpoint-id");
        let inputs, pencilButton;
        
        if (isCheckpoint) {
          inputs = clause.querySelectorAll("textarea");
        } else {
          // For clauses, only get the title input (second input)
          const allInputs = clause.querySelectorAll("input");
          inputs = allInputs.length > 1 ? [allInputs[1]] : [];
        }
        
        pencilButton = clause.querySelector(
          "button[data-action*='toggleEdit']"
        );
        
        if (inputs.length > 0 && pencilButton) {
          // For clauses, save on blur; for checkpoints, just exit
          if (!isCheckpoint) {
            // Auto-save clause on blur
            this.saveClause({ currentTarget: clause });
          } else {
            this.exitEditMode(inputs, pencilButton);
          }
        }
      });
    }
  }

  toggleEdit(event) {
    event.preventDefault();
    event.stopPropagation();

    const checkpointContainer = event.currentTarget.closest(
      "[data-checkpoint-id]"
    );

    let container, inputs, pencilButton;

    if (checkpointContainer) {
      container = checkpointContainer;
      inputs = checkpointContainer.querySelectorAll("textarea");
      pencilButton = event.currentTarget;
    } else {
      const clauseDiv = event.currentTarget.closest(".clause-hierarchy");
      container = clauseDiv;
      // Only get the title input (second input), not the code input (first input)
      const allInputs = clauseDiv.querySelectorAll("input");
      inputs = allInputs.length > 1 ? [allInputs[1]] : [];
      pencilButton = event.currentTarget;
    }

    const isEditing = container.classList.contains("editing-mode");

    if (isEditing) {
      container.classList.remove("editing-mode");
      this.exitEditMode(inputs, pencilButton);
    } else {
      container.classList.add("editing-mode");
      this.enterEditMode(inputs, pencilButton);
    }
  }

  enterEditMode(inputs, pencilButton) {
    const isCheckpoint =
      inputs[0]?.tagName === "TEXTAREA" && inputs.length === 1;
    const isClause = inputs[0]?.tagName === "INPUT" && !isCheckpoint;

    if (isCheckpoint) {
      this.enterCheckpointEditMode(inputs, pencilButton);
    } else if (isClause) {
      this.enterClauseEditMode(inputs, pencilButton);
    }
  }

  enterClauseEditMode(inputs, pencilButton) {
    const clauseContainer = inputs[0].closest(".clause-hierarchy");

    if (inputs[0]) {
      inputs[0].dataset.originalValue = inputs[0].value;
    }

    inputs.forEach((input) => {
      input.readOnly = false;
      input.classList.remove("bg-transparent");
      input.classList.add("border", "border-gray-300", "bg-white");
      input.addEventListener("keydown", this.handleClauseInputKeydown.bind(this));
      input.addEventListener("blur", this.handleClauseInputBlur.bind(this));
    });

    if (clauseContainer && !clauseContainer.querySelector(".clause-edit-buttons")) {
      const cancelText = this.escapeHtml(this.cancelLabelValue);
      const saveText = this.escapeHtml(this.saveLabelValue);
      const buttonsHTML = `
        <div class="clause-edit-buttons flex items-center gap-2 ml-2">
          <button class="px-3 py-1.5 text-sm text-gray-600 hover:text-gray-800 hover:bg-gray-100 rounded transition-colors" data-action="click->clause-editor#cancelEditClause">
            ${cancelText}
          </button>
          <button class="px-4 py-1.5 bg-[#5C3984] text-white text-sm rounded hover:bg-[#4A2F6B] transition-colors" data-action="click->clause-editor#saveClause">
            ${saveText}
          </button>
        </div>
      `;
      const flexContainer = inputs[0].closest(".flex.items-center.space-x-3");
      if (flexContainer) {
        flexContainer.insertAdjacentHTML("beforeend", buttonsHTML);
      } else {
        const inputWrapper = inputs[0].parentElement;
        if (inputWrapper) {
          inputWrapper.insertAdjacentHTML("afterend", buttonsHTML);
        }
      }
    }
  }

  enterCheckpointEditMode(inputs, pencilButton) {
    const checkpointContainer = inputs[0].closest("[data-checkpoint-id]");

    if (inputs[0]) {
      inputs[0].dataset.originalValue = inputs[0].value;
    }

    inputs.forEach((input) => {
      input.readOnly = false;
      input.classList.remove("bg-gray-50", "overflow-hidden");
      input.classList.add(
        "min-h-[200px]",
        "p-4",
        "pb-16",
        "rounded-lg",
        "border-[#5C3984]"
      );
      input.style.resize = "vertical";

      const textareaWrapper = input.parentElement;
      textareaWrapper.style.position = "relative";

      const dragIcon = checkpointContainer.querySelector("[data-drag-handle]");
      if (dragIcon) {
        dragIcon.style.display = "none";
      }

      if (pencilButton) {
        pencilButton.style.display = "none";
      }

      const deleteButton = checkpointContainer.querySelector(
        "button[data-action*='deleteCheckpoint']"
      );
      if (deleteButton) {
        deleteButton.style.display = "none";
      }

      if (!checkpointContainer.querySelector(".checkpoint-edit-buttons")) {
        const cancelText = this.escapeHtml(this.cancelLabelValue);
        const saveChangesText = this.escapeHtml(this.saveChangesLabelValue);
        const buttonsHTML = `
          <div class="checkpoint-edit-buttons absolute bottom-4 right-6 flex items-center gap-2 bg-white">
            <button class="px-3 py-1.5 text-sm text-gray-600 hover:text-gray-800 hover:bg-gray-100 rounded transition-colors" data-action="click->clause-editor#cancelEdit">
              ${cancelText}
            </button>
            <button class="px-4 py-1.5 bg-[#5C3984] text-white text-sm rounded hover:bg-[#4A2F6B] transition-colors" data-action="click->clause-editor#saveCheckpoint">
              ${saveChangesText}
            </button>
          </div>
        `;
        textareaWrapper.insertAdjacentHTML("beforeend", buttonsHTML);
      }
    });
  }

  handleClauseInputKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      this.saveClause(event);
    } else if (event.key === "Escape") {
      event.preventDefault();
      this.cancelEditClause(event);
    }
  }

  handleClauseInputBlur(event) {
    // Don't save if clicking on save/cancel buttons
    const relatedTarget = event.relatedTarget;
    if (relatedTarget && (
      relatedTarget.closest("button[data-action*='saveClause']") ||
      relatedTarget.closest("button[data-action*='cancelEditClause']")
    )) {
      return;
    }
    
    // Small delay to allow button clicks to register
    setTimeout(() => {
      const clauseContainer = event.target.closest(".clause-hierarchy");
      if (clauseContainer && clauseContainer.classList.contains("editing-mode")) {
        this.saveClause({ target: event.target, currentTarget: clauseContainer });
      }
    }, 100);
  }

  exitEditMode(inputs, pencilButton) {
    const isCheckpoint =
      inputs[0]?.tagName === "TEXTAREA" && inputs.length === 1;
    const isClause = inputs[0]?.tagName === "INPUT" && !isCheckpoint;

    if (isCheckpoint) {
      this.exitCheckpointEditMode(inputs, pencilButton);
    } else if (isClause) {
      this.exitClauseEditMode(inputs, pencilButton);
    }
  }

  exitClauseEditMode(inputs, pencilButton) {
    const clauseContainer = inputs[0].closest(".clause-hierarchy");

    inputs.forEach((input) => {
      input.readOnly = true;
      input.classList.add("bg-transparent");
      input.classList.remove("border", "border-gray-300", "bg-white");
      input.removeEventListener("keydown", this.handleClauseInputKeydown.bind(this));
      input.removeEventListener("blur", this.handleClauseInputBlur.bind(this));
    });

    if (clauseContainer) {
      const buttonsContainer = clauseContainer.querySelector(".clause-edit-buttons");
      if (buttonsContainer) {
        buttonsContainer.remove();
      }
    }
  }

  exitCheckpointEditMode(inputs, pencilButton) {
    const checkpointContainer = inputs[0].closest("[data-checkpoint-id]");

    if (!checkpointContainer) {
      console.error("checkpointContainer not found in exitEditMode");
      return;
    }

    inputs.forEach((input) => {
      input.readOnly = true;
      input.classList.add("bg-gray-50", "overflow-hidden");
      input.classList.remove(
        "min-h-[200px]",
        "p-4",
        "pb-16",
        "rounded-lg",
        "border-[#5C3984]",
        "border",
        "border-gray-300",
        "bg-white"
      );
      input.rows = 1;
      input.style.height = "";
      input.style.resize = "none";

      const textareaWrapper = input.parentElement;
      textareaWrapper.style.position = "";

      const dragIcon = checkpointContainer.querySelector("[data-drag-handle]");
      if (dragIcon) {
        dragIcon.style.display = "block";
      }

      let editButton = checkpointContainer.querySelector("button[data-action*='toggleEdit']");
      if (!editButton) {
        editButton = checkpointContainer.querySelector("button[data-action*='clause-editor#toggleEdit']");
      }
      if (!editButton) {
        const pencilImg = checkpointContainer.querySelector("img[src*='pencil-icon']");
        editButton = pencilImg?.closest("button");
      }
      if (editButton) {
        editButton.style.display = "inline-block";
        editButton.style.visibility = "visible";
        editButton.style.opacity = "1";
        editButton.removeAttribute("hidden");
      } else {
        console.error("Edit button not found in checkpoint container. HTML:", checkpointContainer.innerHTML);
      }

      let deleteButton = checkpointContainer.querySelector("button[data-action*='deleteCheckpoint']");
      if (!deleteButton) {
        deleteButton = checkpointContainer.querySelector("button[data-action*='clause-editor#deleteCheckpoint']");
      }
      if (!deleteButton) {
        const deleteImg = checkpointContainer.querySelector("img[src*='delete-clause-icon']");
        deleteButton = deleteImg?.closest("button");
      }
      if (deleteButton) {
        deleteButton.style.display = "inline-block";
        deleteButton.style.visibility = "visible";
        deleteButton.style.opacity = "1";
        deleteButton.removeAttribute("hidden");
      } else {
        console.error("Delete button not found in checkpoint container. HTML:", checkpointContainer.innerHTML);
      }

      const buttonsContainer = checkpointContainer.querySelector(".checkpoint-edit-buttons");
      if (buttonsContainer) {
        buttonsContainer.remove();
      }
    });
  }

  // ============================================
  // CRUD Operations
  // ============================================

  addClause(event) {
    event.preventDefault();
    const clauseDiv = event.currentTarget.closest(".clause-hierarchy");
    const parentId = clauseDiv.dataset.clauseId;
    const level = parseInt(clauseDiv.dataset.level || 0) + 1;
    const tempId = `tmp_${crypto.randomUUID?.() || Date.now()}`;

    this.pending.clauses.created.push({
      tempId,
      parentId,
      title: this.newClauseDefaultValue,
      code: "?"
    });

    const childrenDiv = clauseDiv.querySelector("[data-children-container]");
    if (!childrenDiv) return;

    const html = this.getClauseHTML(tempId, parentId, level, this.newClauseDefaultValue, "?");
    childrenDiv.insertAdjacentHTML("beforeend", html);
    this.initializeClauseSortables();

    const newClauseElement = childrenDiv.querySelector(`[data-clause-id="${tempId}"]`);
    if (newClauseElement) {
      const allInputs = newClauseElement.querySelectorAll("input");
      const titleInput = allInputs.length > 1 ? allInputs[1] : null;
      const pencilButton = newClauseElement.querySelector("button[data-action*='toggleEdit']");
      if (titleInput && pencilButton) {
        titleInput.dataset.originalValue = this.newClauseDefaultValue;
        titleInput.value = "";
        newClauseElement.classList.add("editing-mode");
        this.enterEditMode([titleInput], pencilButton);
        titleInput.focus();
      }
    }
    this.updateDirtyIndicator();
  }

  addRootClause(event) {
    event.preventDefault();
    const button = event.currentTarget;
    const standardVersionId = button.dataset.standardVersionId;
    const rootContainer = this.element.querySelector("#root-clauses-container");

    if (!standardVersionId) {
      alert("Standard version ID is required");
      return;
    }

    const tempId = `tmp_${crypto.randomUUID?.() || Date.now()}`;
    this.pending.clauses.created.push({
      tempId,
      parentId: null,
      standardVersionId,
      title: this.newClauseDefaultValue,
      code: "?"
    });

    if (rootContainer) {
      rootContainer.innerHTML = "";
      const html = this.getClauseHTML(tempId, null, 0, this.newClauseDefaultValue, "?");
      rootContainer.insertAdjacentHTML("beforeend", html);
      this.initializeClauseSortables();

      const newClauseElement = rootContainer.querySelector(`[data-clause-id="${tempId}"]`);
      if (newClauseElement) {
        const allInputs = newClauseElement.querySelectorAll("input");
        const titleInput = allInputs.length > 1 ? allInputs[1] : null;
        const pencilButton = newClauseElement.querySelector("button[data-action*='toggleEdit']");
        if (titleInput && pencilButton) {
          titleInput.dataset.originalValue = this.newClauseDefaultValue;
          titleInput.value = "";
          newClauseElement.classList.add("editing-mode");
          this.enterEditMode([titleInput], pencilButton);
          titleInput.focus();
        }
      }
    }
    this.updateDirtyIndicator();
  }

  addCheckpoint(event) {
    event.preventDefault();
    const clauseDiv = event.currentTarget.closest(".clause-hierarchy");
    const clauseId = clauseDiv.dataset.clauseId;

    const checkpointsContainer = clauseDiv.querySelector(
      "[data-checkpoints-container]"
    );
    const checkpointsListContainer = checkpointsContainer?.querySelector(
      "[data-checkpoints-list]"
    );

    if (!checkpointsListContainer) {
      alert("Error: Checkpoints container not found");
      return;
    }

    // Show the "Checkpoints:" label if hidden
    const checkpointsLabel = checkpointsListContainer.querySelector(
      "[data-checkpoints-label]"
    );
    if (checkpointsLabel) {
      checkpointsLabel.style.display = "block";
    }

    // Hide empty hint if visible
    const emptyHint =
      checkpointsListContainer.querySelector("[data-empty-hint]");
    if (emptyHint) {
      emptyHint.style.display = "none";
    }

    // Create a temporary checkpoint (no server call yet)
    const tempId = `tmp_${crypto.randomUUID?.() || Date.now()}`;
    const newCheckpoint = this.getCheckpointHTML(tempId, this.newCheckpointDefaultValue);

    // Store clause_id in the checkpoint element for later use
    const tempDiv = document.createElement('div');
    tempDiv.innerHTML = newCheckpoint;
    const checkpointElement = tempDiv.firstElementChild;
    checkpointElement.dataset.clauseId = clauseId;

    if (emptyHint) {
      emptyHint.insertAdjacentElement("beforebegin", checkpointElement);
    } else {
      checkpointsListContainer.appendChild(checkpointElement);
    }

    this.pending.checkpoints.created.push({
      tempId,
      clauseId,
      text: ""
    });
    this.updateDirtyIndicator();

    // Reinitialize Sortable for the checkpoint container
    this.initializeCheckpointSortables();

    // Automatically enter edit mode for the new checkpoint
    const textarea = checkpointElement.querySelector("textarea");
    const pencilButton = checkpointElement.querySelector(
      "button[data-action*='toggleEdit']"
    );
    if (textarea && pencilButton) {
      // Store original value (empty for new checkpoint)
      textarea.dataset.originalValue = "";
      // Clear the default text
      textarea.value = "";
      // Mark container as editing
      checkpointElement.classList.add("editing-mode");
      // Use enterEditMode to ensure consistent state
      this.enterEditMode([textarea], pencilButton);
      // Focus on textarea
      textarea.focus();
    }
  }

  async deleteClause(event) {
    event.preventDefault();

    const clauseDiv = event.currentTarget.closest(".clause-hierarchy");
    const clauseId = clauseDiv.dataset.clauseId;

    const confirmed = await this.showConfirmation(
      this.confirmDeleteClauseMessageValue,
      { title: this.confirmDeleteTitleValue, confirmText: this.deleteLabelValue, buttonStyle: "danger" }
    );

    if (!confirmed) return;

    if (String(clauseId).startsWith("tmp_")) {
      this.pending.clauses.created = this.pending.clauses.created.filter((c) => c.tempId !== clauseId);
    } else {
      this.pending.clauses.deleted.push(clauseId);
    }
    clauseDiv.remove();
    this.updateDirtyIndicator();
  }

  async deleteCheckpoint(event) {
    event.preventDefault();

    const checkpointDiv = event.currentTarget.closest("[data-checkpoint-id]");
    const checkpointId = checkpointDiv?.dataset.checkpointId;

    const confirmed = await this.showConfirmation(
      this.confirmDeleteCheckpointMessageValue,
      { title: this.confirmDeleteTitleValue, confirmText: this.deleteLabelValue, buttonStyle: "danger" }
    );

    if (!confirmed) return;

    const checkpointsContainer = checkpointDiv.closest("[data-checkpoints-container]");

    if (!checkpointId) {
      checkpointDiv.remove();
      this.cleanupEmptyCheckpointContainer(checkpointsContainer);
      this.updateDirtyIndicator();
      return;
    }

    if (String(checkpointId).startsWith("tmp_")) {
      this.pending.checkpoints.created = this.pending.checkpoints.created.filter(
        (c) => c.tempId !== checkpointId
      );
    } else {
      this.pending.checkpoints.deleted.push(checkpointId);
    }
    checkpointDiv.remove();
    this.cleanupEmptyCheckpointContainer(checkpointsContainer);
    this.updateDirtyIndicator();
  }

  saveClause(event) {
    if (event && event.preventDefault) {
      event.preventDefault();
    }

    const clauseContainer = event?.currentTarget?.closest(".clause-hierarchy") ||
      (event?.currentTarget?.classList?.contains("clause-hierarchy") ? event.currentTarget : null) ||
      (event?.target?.closest(".clause-hierarchy"));

    if (!clauseContainer) return;

    const allInputs = clauseContainer.querySelectorAll("input");
    const codeInput = allInputs.length > 0 ? allInputs[0] : null;
    const titleInput = allInputs.length > 1 ? allInputs[1] : null;
    const pencilButton = clauseContainer.querySelector("button[data-action*='toggleEdit']");
    const clauseId = clauseContainer.dataset.clauseId;

    if (!titleInput || !clauseId) return;

    const originalTitle = titleInput.dataset.originalValue || "";
    const originalCode = codeInput ? (codeInput.dataset.originalValue ?? codeInput.value) : "";
    if (titleInput.value === originalTitle && (!codeInput || codeInput.value === originalCode)) {
      clauseContainer.classList.remove("editing-mode");
      if (pencilButton) this.exitEditMode([titleInput], pencilButton);
      return;
    }

    // Pending only: no API call
    if (String(clauseId).startsWith("tmp_")) {
      const created = this.pending.clauses.created.find((c) => c.tempId === clauseId);
      if (created) {
        created.title = titleInput.value;
        if (codeInput) created.code = codeInput.value;
      }
    } else {
      this.pending.clauses.updated[clauseId] = {
        title: titleInput.value,
        ...(codeInput && { code: codeInput.value })
      };
    }

    titleInput.dataset.originalValue = titleInput.value;
    if (codeInput) codeInput.dataset.originalValue = codeInput.value;
    clauseContainer.classList.remove("editing-mode");
    if (pencilButton) this.exitEditMode([titleInput], pencilButton);
    this.updateDirtyIndicator();
  }

  saveCheckpoint(event) {
    event.preventDefault();
    const checkpointContainer = event.currentTarget.closest("[data-checkpoint-id]");
    const textarea = checkpointContainer.querySelector("textarea");
    const pencilButton = checkpointContainer.querySelector("button[data-action*='toggleEdit']");
    const checkpointId = checkpointContainer.dataset.checkpointId;

    if (!textarea || !pencilButton || !checkpointId) return;

    // Pending only: no API call
    if (checkpointId.startsWith("tmp_")) {
      const created = this.pending.checkpoints.created.find((c) => c.tempId === checkpointId);
      if (created) created.text = textarea.value;
      else {
        const clauseId = checkpointContainer.dataset.clauseId;
        if (clauseId) {
          this.pending.checkpoints.created.push({
            tempId: checkpointId,
            clauseId,
            text: textarea.value
          });
        }
      }
    } else {
      this.pending.checkpoints.updated[checkpointId] = { text: textarea.value };
    }

    textarea.dataset.originalValue = textarea.value;
    checkpointContainer.classList.remove("editing-mode");
    this.exitEditMode([textarea], pencilButton);
    this.updateDirtyIndicator();

    const editBtn = checkpointContainer.querySelector("button[data-action*='toggleEdit']");
    const deleteBtn = checkpointContainer.querySelector("button[data-action*='deleteCheckpoint']");
    if (editBtn) {
      editBtn.style.display = "inline-block";
      editBtn.style.visibility = "visible";
      editBtn.style.opacity = "1";
    }
    if (deleteBtn) {
      deleteBtn.style.display = "inline-block";
      deleteBtn.style.visibility = "visible";
      deleteBtn.style.opacity = "1";
    }
  }

  async cancelEditClause(event) {
    event.preventDefault();
    const clauseContainer = event.currentTarget.closest(".clause-hierarchy");
    if (!clauseContainer) return;

    const allInputs = clauseContainer.querySelectorAll("input");
    const titleInput = allInputs.length > 1 ? allInputs[1] : null;
    const pencilButton = clauseContainer.querySelector(
      "button[data-action*='toggleEdit']"
    );

    if (!titleInput || !pencilButton) return;

    const originalValue = titleInput.dataset.originalValue || "";
    titleInput.value = originalValue;
    clauseContainer.classList.remove("editing-mode");
    this.exitEditMode([titleInput], pencilButton);
  }

  cancelEdit(event) {
    event.preventDefault();
    const checkpointContainer = event.currentTarget.closest("[data-checkpoint-id]");
    const textarea = checkpointContainer.querySelector("textarea");
    const pencilButton = checkpointContainer.querySelector("button[data-action*='toggleEdit']");

    if (!textarea || !pencilButton) return;

    const checkpointId = checkpointContainer.dataset.checkpointId;
    const originalValue = textarea.dataset.originalValue || "";

    if (originalValue === "" || originalValue === this.newCheckpointDefaultValue) {
      if (checkpointId.startsWith("tmp_")) {
        this.pending.checkpoints.created = this.pending.checkpoints.created.filter(
          (c) => c.tempId !== checkpointId
        );
      }
      const checkpointsContainer = checkpointContainer.closest("[data-checkpoints-container]");
      checkpointContainer.remove();
      this.cleanupEmptyCheckpointContainer(checkpointsContainer);
      this.updateDirtyIndicator();
    } else {
      textarea.value = originalValue;
      checkpointContainer.classList.remove("editing-mode");
      this.exitEditMode([textarea], pencilButton);
    }
  }

  // ============================================
  // HTML Generation Methods
  // ============================================

  getCheckpointHTML(id, text) {
    const checkpointId = id || `tmp_${crypto.randomUUID?.() || Date.now()}`;
    const checkpointText = text || this.newCheckpointDefaultValue;

    // Use asset paths from data attributes, fallback to default paths
    const pencilIconPath = this.pencilIconPathValue || "/assets/pencil-icon.svg";
    const deleteIconPath = this.deleteIconPathValue || "/assets/delete-clause-icon.svg";
    const translatingText = this.escapeHtml(this.translatingLabelValue);
    const deleteCheckpointTitle = this.escapeAttr(this.deleteCheckpointLabelValue);

    return `
      <div class="flex items-center space-x-2 p-2 bg-gray-50 rounded" data-checkpoint-id="${checkpointId}">
        <!-- Translation spinner (hidden by default) -->
        <div data-translation-spinner class="hidden ml-2 flex items-center gap-2">
          <svg class="w-4 h-4 animate-spin text-[#5C3984]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
          <span class="text-xs text-[#5C3984] font-medium">${translatingText}</span>
        </div>
        <div data-drag-handle class="cursor-move p-1 hover:bg-gray-100 rounded">
          <div class="grid grid-cols-3 gap-1 w-5">
            <div class="w-1 h-1 bg-[#5C3984] rounded-full"></div>
            <div class="w-1 h-1 bg-[#5C3984] rounded-full"></div>
            <div class="w-1 h-1 bg-[#5C3984] rounded-full"></div>
            <div class="w-1 h-1 bg-[#5C3984] rounded-full"></div>
            <div class="w-1 h-1 bg-[#5C3984] rounded-full"></div>
            <div class="w-1 h-1 bg-[#5C3984] rounded-full"></div>
          </div>
        </div>
        
        <textarea rows="1" readonly class="flex-1 text-sm text-[#0D1120] border border-gray-300 bg-gray-50 rounded px-2 py-1 resize-none overflow-hidden">${checkpointText}</textarea>
        <button class="p-1 text-gray-600 hover:bg-gray-100 rounded transition-colors" data-action="click->clause-editor#toggleEdit">
          <img src="${pencilIconPath}" class="w-4 h-4" />
        </button>
        <button class="p-1 text-gray-600 hover:text-red-600 transition-colors" data-action="click->clause-editor#deleteCheckpoint" title="${deleteCheckpointTitle}">
          <img src="${deleteIconPath}" class="w-4 h-4" />
        </button>
      </div>
    `;
  }

  showTranslationNotification(message) {
    const bgColor = 'bg-[#FFFFFF] border-[#E3E3E3] border-l-4 border-l-[#5C3984]';
    const icon = '<svg class="w-5 h-5 text-[#5C3984]" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"/></svg>';

    const notificationHtml = `
      <div 
        data-toast-target="notification"
        class="${bgColor} rounded-lg shadow-lg p-4 flex items-start gap-3 transform opacity-0 translate-x-full transition ease-out duration-300"
      >
        ${icon}
        <div class="flex-1 text-sm text-[#0D1120] font-medium">
          ${message}
        </div>
        <button 
          data-action="click->toast#close"
          class="text-gray-400 hover:text-gray-600 transition-colors"
        >
          <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"/>
          </svg>
        </button>
      </div>
    `;

    // Dispatch custom event for toast controller to handle
    const event = new CustomEvent('toast:show', {
      detail: { notificationHtml },
      bubbles: true
    });
    document.dispatchEvent(event);
  }

  addReviewBadge(container, languages) {
    const existingBadge = container.querySelector('.translation-review-badge');
    if (existingBadge) return;
    
    const badge = document.createElement('span');
    badge.className = 'translation-review-badge inline-flex items-center px-2 py-1 rounded text-xs font-medium bg-[#F6EEFF] text-[#5C3984] border border-[#D6C4ED] ml-2';
    badge.innerHTML = `
      <svg class="w-3 h-3 mr-1" fill="currentColor" viewBox="0 0 20 20">
        <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"/>
      </svg>
      Modified in ${languages.join(', ')}
    `;
    
    const titleInput = container.querySelector('input[type="text"]');
    if (titleInput && titleInput.parentElement) {
      titleInput.parentElement.appendChild(badge);
    }
  }

  async markAsReviewed(event) {
    event.preventDefault();
    const clauseId = event.currentTarget.dataset.clauseId;
    
    try {
      const response = await fetch(`/clauses/${clauseId}/mark_reviewed`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
        },
        body: JSON.stringify({
          language_code: document.documentElement.lang || 'en'
        })
      });
      
      if (response.ok) {
        // Remove review indicators
        const clauseContainer = document.querySelector(`[data-clause-id="${clauseId}"]`);
        if (clauseContainer) {
          clauseContainer.classList.remove('border-l-4', 'border-l-[#5C3984]');
          clauseContainer.dataset.needsReview = 'false';
          
          // Find the parent container that holds badges and button
          const markButton = event.currentTarget;
          const badgesContainer = markButton?.closest('.flex.items-center.gap-2');
          
          // Remove the warning badge (translation outdated)
          const warningBadge = clauseContainer.querySelector('span[title*="Translation outdated"], span[title*="الترجمة قديمة"]');
          if (warningBadge) {
            warningBadge.remove();
          }
          
          // Remove review badges - look for spans with purple background
          const allSpans = clauseContainer.querySelectorAll('span.inline-flex');
          allSpans.forEach(badge => {
            const classes = badge.className;
            // Check if it's a review badge (has purple background or translation-review-badge class)
            if (classes.includes('F6EEFF') || classes.includes('translation-review-badge') || 
                classes.includes('text-[#5C3984]')) {
              badge.remove();
            }
          });
          
          // Remove "Mark as Reviewed" button - try multiple methods
          // First try event.currentTarget
          if (markButton) {
            markButton.style.display = 'none';
            markButton.remove();
          }
          // Fallback: find button by data attribute (more reliable)
          const buttonByAttr = clauseContainer.querySelector(`button[data-action*="markAsReviewed"][data-clause-id="${clauseId}"]`);
          if (buttonByAttr) {
            buttonByAttr.style.display = 'none';
            buttonByAttr.remove();
          }
          // Also try finding by text content as last resort
          const allButtons = clauseContainer.querySelectorAll('button');
          allButtons.forEach(btn => {
            if (btn.textContent.trim() === this.markAsReviewedLabelValue.trim()) {
              btn.style.display = 'none';
              btn.remove();
            }
          });
          
          // If badges container exists and is now empty (or only has other language badges), hide it
          if (badgesContainer) {
            const remainingChildren = badgesContainer.querySelectorAll('span, button');
            if (remainingChildren.length === 0) {
              badgesContainer.remove();
            }
          }
        }
      } else {
        // Try to parse as JSON, but handle HTML error pages
        let errorMessage = "Unknown error";
        try {
          const error = await response.json();
          errorMessage = error.error || errorMessage;
        } catch (parseError) {
          // If response is not JSON (e.g., HTML error page), get text
          const text = await response.text();
          console.error('Non-JSON response:', text.substring(0, 200));
          errorMessage = `Server error (${response.status}): ${response.statusText}`;
        }
        alert(`Failed to mark as reviewed: ${errorMessage}`);
      }
    } catch (error) {
      console.error('Error marking as reviewed:', error);
      alert('An error occurred while marking as reviewed. Please try again.');
    }
  }

  async markCheckpointAsReviewed(event) {
    event.preventDefault();
    const checkpointId = event.currentTarget.dataset.checkpointId;
    
    try {
      const response = await fetch(`/checkpoints/${checkpointId}/mark_reviewed`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
        },
        body: JSON.stringify({
          language_code: document.documentElement.lang || 'en'
        })
      });
      
      if (response.ok) {
        // Remove review indicators
        const checkpointContainer = document.querySelector(`[data-checkpoint-id="${checkpointId}"]`);
        if (checkpointContainer) {
          checkpointContainer.classList.remove('border-l-4', 'border-l-[#5C3984]');
          checkpointContainer.dataset.needsReview = 'false';
          
          // Find the parent container that holds badges
          const markButton = event.currentTarget;
          const badgesContainer = checkpointContainer.querySelector('.flex.flex-col.gap-1');
          
          // Remove the warning badge (translation outdated) - look for emoji or specific badge
          const warningBadge = checkpointContainer.querySelector('span[title*="Translation outdated"], span[title*="الترجمة قديمة"]');
          if (warningBadge) {
            warningBadge.remove();
          }
          
          // Remove review badges - look for spans with purple background
          const allSpans = checkpointContainer.querySelectorAll('span.inline-flex');
          allSpans.forEach(badge => {
            const classes = badge.className;
            // Check if it's a review badge (has purple background)
            if (classes.includes('F6EEFF') || classes.includes('text-[#5C3984]')) {
              badge.remove();
            }
          });
          
          // Remove "Mark as Reviewed" button - try multiple methods
          // First try event.currentTarget
          if (markButton) {
            markButton.style.display = 'none';
            markButton.remove();
          }
          // Fallback: find button by data attribute (more reliable)
          const buttonByAttr = checkpointContainer.querySelector(`button[data-action*="markCheckpointAsReviewed"][data-checkpoint-id="${checkpointId}"]`);
          if (buttonByAttr) {
            buttonByAttr.style.display = 'none';
            buttonByAttr.remove();
          }
          // Also try finding by text content as last resort
          const allButtons = checkpointContainer.querySelectorAll('button');
          allButtons.forEach(btn => {
            if (btn.textContent.trim() === this.markAsReviewedLabelValue.trim()) {
              btn.style.display = 'none';
              btn.remove();
            }
          });
          
          // If badges container exists and is now empty, remove it
          if (badgesContainer) {
            const remainingChildren = badgesContainer.querySelectorAll('span');
            if (remainingChildren.length === 0) {
              badgesContainer.remove();
            }
          }
        }
      } else {
        // Try to parse as JSON, but handle HTML error pages
        let errorMessage = "Unknown error";
        try {
          const error = await response.json();
          errorMessage = error.error || errorMessage;
        } catch (parseError) {
          // If response is not JSON (e.g., HTML error page), get text
          const text = await response.text();
          console.error('Non-JSON response:', text.substring(0, 200));
          errorMessage = `Server error (${response.status}): ${response.statusText}`;
        }
        alert(`Failed to mark as reviewed: ${errorMessage}`);
      }
    } catch (error) {
      console.error('Error marking checkpoint as reviewed:', error);
      alert('An error occurred while marking as reviewed. Please try again.');
    }
  }
}
