export const NotebookItem = {
  mounted() {
    this.heartbeatTimer = null
    this.hasLock = false

    this.itemTarget = () => ({
      path: this.el.dataset.path,
      node_id: this.el.dataset.nodeId,
      page_id: this.el.dataset.pageId,
    })

    this.startHeartbeat = () => {
      this.stopHeartbeat()
      this.heartbeatTimer = setInterval(() => {
        this.pushEvent("item_lock_heartbeat", this.itemTarget())
      }, 4000)
    }

    this.stopHeartbeat = () => {
      if (this.heartbeatTimer) {
        clearInterval(this.heartbeatTimer)
        this.heartbeatTimer = null
      }
    }

    this.onFocus = () => {
      if (!this.hasLock) {
        this.pushEvent("item_lock_acquire", this.itemTarget())
        this.hasLock = true
      }

      this.startHeartbeat()
    }

    this.onBlur = () => {
      this.stopHeartbeat()

      if (this.hasLock) {
        this.pushEvent("item_lock_release", this.itemTarget())
        this.hasLock = false
      }
    }

    this.resize = () => {
      this.el.style.height = "auto"
      this.el.style.height = `${this.el.scrollHeight}px`
    }

    this.resize()

    this.handleEvent("focus-item", ({path, page_id}) => {
      if (this.el.dataset.path === path && this.el.dataset.pageId === String(page_id)) {
        this.el.focus()
        const len = this.el.value.length
        this.el.setSelectionRange(len, len)
        this.resize()
      }
    })

    this.el.addEventListener("input", this.resize)
    this.el.addEventListener("focus", this.onFocus)
    this.el.addEventListener("blur", this.onBlur)

    this.el.addEventListener("keydown", event => {
      if (event.key === "Tab") {
        event.preventDefault()

        if (event.shiftKey) {
          this.pushEvent("item_outdent", {
            path: this.el.dataset.path,
            node_id: this.el.dataset.nodeId,
            page_id: this.el.dataset.pageId,
            text: this.el.value,
          })
        } else {
          this.pushEvent("item_indent", {
            path: this.el.dataset.path,
            node_id: this.el.dataset.nodeId,
            page_id: this.el.dataset.pageId,
            text: this.el.value,
          })
        }
      }

      if (event.key === "Enter" && !event.shiftKey) {
        event.preventDefault()
        this.pushEvent("item_enter", {
          path: this.el.dataset.path,
          node_id: this.el.dataset.nodeId,
          page_id: this.el.dataset.pageId,
          text: this.el.value,
        })
      }

      if ((event.key === "Backspace" || event.key === "Delete") && this.el.value === "") {
        event.preventDefault()

        if (document.activeElement === this.el) {
          this.el.blur()
        }

        this.pushEvent("item_delete_empty", {
          path: this.el.dataset.path,
          node_id: this.el.dataset.nodeId,
          page_id: this.el.dataset.pageId,
          text: this.el.value,
        })
      }
    })
  },

  updated() {
    this.el.style.height = "auto"
    this.el.style.height = `${this.el.scrollHeight}px`

    if (this.el.disabled && document.activeElement === this.el) {
      this.el.blur()
    }
  },

  destroyed() {
    this.stopHeartbeat()

    if (this.hasLock) {
      this.pushEvent("item_lock_release", this.itemTarget())
      this.hasLock = false
    }

    this.el.removeEventListener("input", this.resize)
    this.el.removeEventListener("focus", this.onFocus)
    this.el.removeEventListener("blur", this.onBlur)
  },
}

export const ItemOptionsBubble = {
  mounted() {
    this.heartbeatTimer = null
    this.hasLock = false

    this.itemTarget = () => ({
      path: this.el.dataset.path,
      page_id: this.el.dataset.pageId,
    })

    this.startHeartbeat = () => {
      this.stopHeartbeat()
      this.heartbeatTimer = setInterval(() => {
        this.pushEvent("item_lock_heartbeat", this.itemTarget())
      }, 4000)
    }

    this.stopHeartbeat = () => {
      if (this.heartbeatTimer) {
        clearInterval(this.heartbeatTimer)
        this.heartbeatTimer = null
      }
    }

    this.acquireLock = () => {
      if (!this.hasLock) {
        this.pushEvent("item_lock_acquire", this.itemTarget())
        this.hasLock = true
      }

      this.startHeartbeat()
    }

    this.releaseLock = () => {
      this.stopHeartbeat()

      if (this.hasLock) {
        this.pushEvent("item_lock_release", this.itemTarget())
        this.hasLock = false
      }
    }

    this.onToggle = () => {
      if (this.el.open) {
        this.acquireLock()
      } else {
        this.releaseLock()
      }
    }

    this.onDocumentClick = event => {
      if (this.el.open && !this.el.contains(event.target)) {
        this.el.open = false
      }
    }

    this.onEscape = event => {
      if (event.key === "Escape") {
        this.el.open = false
      }
    }

    this.el.addEventListener("toggle", this.onToggle)
    document.addEventListener("click", this.onDocumentClick)
    document.addEventListener("keydown", this.onEscape)

    if (this.el.open) {
      this.acquireLock()
    }
  },

  beforeUpdate() {
    this.previousNodeId = this.el.dataset.nodeId
    this.previousPath = this.el.dataset.path
    this.wasOpen = this.el.open

    if (this.el.contains(document.activeElement)) {
      this.focusedElementName = document.activeElement.name
      this.selectionStart = document.activeElement.selectionStart
      this.selectionEnd = document.activeElement.selectionEnd
    } else {
      this.focusedElementName = null
      this.selectionStart = null
      this.selectionEnd = null
    }
  },

  updated() {
    const sameItem =
      this.previousNodeId === this.el.dataset.nodeId && this.previousPath === this.el.dataset.path

    if (!this.wasOpen || !sameItem) {
      return
    }

    this.el.open = true

    if (this.focusedElementName === "link") {
      const input = this.el.querySelector('input[name="link"]')

      if (input) {
        input.focus()

        if (this.selectionStart !== null && this.selectionEnd !== null) {
          input.setSelectionRange(this.selectionStart, this.selectionEnd)
        }
      }
    }
  },

  destroyed() {
    this.releaseLock()
    this.el.removeEventListener("toggle", this.onToggle)
    document.removeEventListener("click", this.onDocumentClick)
    document.removeEventListener("keydown", this.onEscape)
  },
}

export const CollaborativeInputLock = {
  mounted() {
    this.heartbeatTimer = null
    this.hasLock = false

    this.lockTarget = () => ({
      path: this.el.dataset.lockPath,
      page_id: this.el.dataset.pageId,
    })

    this.startHeartbeat = () => {
      this.stopHeartbeat()
      this.heartbeatTimer = setInterval(() => {
        this.pushEvent("item_lock_heartbeat", this.lockTarget())
      }, 4000)
    }

    this.stopHeartbeat = () => {
      if (this.heartbeatTimer) {
        clearInterval(this.heartbeatTimer)
        this.heartbeatTimer = null
      }
    }

    this.onFocus = () => {
      if (!this.hasLock) {
        this.pushEvent("item_lock_acquire", this.lockTarget())
        this.hasLock = true
      }

      this.startHeartbeat()
    }

    this.onBlur = () => {
      this.stopHeartbeat()

      if (this.hasLock) {
        this.pushEvent("item_lock_release", this.lockTarget())
        this.hasLock = false
      }
    }

    this.el.addEventListener("focus", this.onFocus)
    this.el.addEventListener("blur", this.onBlur)
  },

  updated() {
    if (this.el.disabled && document.activeElement === this.el) {
      this.el.blur()
    }
  },

  destroyed() {
    this.stopHeartbeat()

    if (this.hasLock) {
      this.pushEvent("item_lock_release", this.lockTarget())
      this.hasLock = false
    }

    this.el.removeEventListener("focus", this.onFocus)
    this.el.removeEventListener("blur", this.onBlur)
  },
}

export const NotebookDnd = {
  mounted() {
    this.dragState = null
    this.dropTarget = null

    this.clearDropTarget = () => {
      if (!this.dropTarget) {
        return
      }

      this.dropTarget.el.classList.remove("ring-2", "ring-primary/45", "bg-primary/8")
      this.dropTarget = null
    }

    this.setDropTarget = nextTarget => {
      if (
        this.dropTarget &&
          this.dropTarget.el === nextTarget.el &&
          this.dropTarget.position === nextTarget.position
      ) {
        return
      }

      this.clearDropTarget()
      this.dropTarget = nextTarget
      this.dropTarget.el.classList.add("ring-2", "ring-primary/45", "bg-primary/8")
    }

    this.cleanupDragState = () => {
      if (this.dragState?.sourceElement) {
        this.dragState.sourceElement.classList.remove("opacity-55")
      }

      this.clearDropTarget()
      this.dragState = null
    }

    this.onDragStart = event => {
      const handle = event.target.closest("[data-dnd-drag-handle]")

      if (!handle) {
        return
      }

      const item = handle.closest("[data-dnd-item]")

      if (!item) {
        return
      }

      this.dragState = {
        sourceElement: item,
        sourcePageId: item.dataset.pageId,
        sourcePath: item.dataset.path,
        sourceNodeId: item.dataset.nodeId,
      }

      event.dataTransfer.effectAllowed = "move"
      event.dataTransfer.setData("text/plain", item.dataset.nodeId || item.dataset.path || "")
      item.classList.add("opacity-55")
    }

    this.onDragOver = event => {
      if (!this.dragState) {
        return
      }

      const targetItem = event.target.closest("[data-dnd-item]")

      if (targetItem) {
        event.preventDefault()

        const rect = targetItem.getBoundingClientRect()
        const position = event.clientY < rect.top + rect.height / 2 ? "before" : "after"

        this.setDropTarget({
          el: targetItem,
          pageId: targetItem.dataset.pageId,
          path: targetItem.dataset.path,
          nodeId: targetItem.dataset.nodeId,
          position,
        })

        return
      }

      const pageTarget = event.target.closest("[data-dnd-page]")

      if (pageTarget) {
        event.preventDefault()

        this.setDropTarget({
          el: pageTarget,
          pageId: pageTarget.dataset.dndPage,
          position: "root_end",
        })
      }
    }

    this.onDrop = event => {
      if (!this.dragState) {
        return
      }

      event.preventDefault()

      const inferredTarget = (() => {
        const item = event.target.closest("[data-dnd-item]")

        if (item) {
          return {
            el: item,
            pageId: item.dataset.pageId,
            path: item.dataset.path,
            nodeId: item.dataset.nodeId,
            position: "after",
          }
        }

        const page = event.target.closest("[data-dnd-page]")

        if (page) {
          return {
            el: page,
            pageId: page.dataset.dndPage,
            position: "root_end",
          }
        }

        return null
      })()

      const target = this.dropTarget || inferredTarget

      if (!target) {
        this.cleanupDragState()
        return
      }

      this.pushEvent("move_item", {
        source_page_id: this.dragState.sourcePageId,
        source_path: this.dragState.sourcePath,
        source_node_id: this.dragState.sourceNodeId,
        target_page_id: target.pageId,
        target_path: target.path,
        target_node_id: target.nodeId,
        position: target.position,
      })

      this.cleanupDragState()
    }

    this.onDragEnd = () => {
      this.cleanupDragState()
    }

    this.el.addEventListener("dragstart", this.onDragStart)
    this.el.addEventListener("dragover", this.onDragOver)
    this.el.addEventListener("drop", this.onDrop)
    this.el.addEventListener("dragend", this.onDragEnd)
  },

  destroyed() {
    this.el.removeEventListener("dragstart", this.onDragStart)
    this.el.removeEventListener("dragover", this.onDragOver)
    this.el.removeEventListener("drop", this.onDrop)
    this.el.removeEventListener("dragend", this.onDragEnd)
    this.cleanupDragState()
  },
}
