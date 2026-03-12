import Quill from "quill"

const NOTEBOOK_IMAGE_POSITION_CLASSES = [
  "notebook-image-left",
  "notebook-image-center",
  "notebook-image-right",
]

const BaseImageFormat = Quill.import("formats/image")

class NotebookImageFormat extends BaseImageFormat {
  static formats(domNode) {
    const formats = super.formats(domNode)
    const className = NOTEBOOK_IMAGE_POSITION_CLASSES.find(token => domNode.classList.contains(token))

    if (className) {
      formats.class = className
    }

    return formats
  }

  format(name, value) {
    if (name === "class") {
      this.domNode.classList.remove(...NOTEBOOK_IMAGE_POSITION_CLASSES)

      if (NOTEBOOK_IMAGE_POSITION_CLASSES.includes(value)) {
        this.domNode.classList.add(value)
      }

      return
    }

    super.format(name, value)
  }
}

Quill.register(NotebookImageFormat, true)

const notebookToolbarMarkup = () => `
  <span class="ql-formats">
    <button class="ql-bold" type="button"></button>
    <button class="ql-italic" type="button"></button>
    <button class="ql-underline" type="button"></button>
    <button class="ql-strike" type="button"></button>
  </span>
  <span class="ql-formats">
    <select class="ql-color"></select>
    <select class="ql-background"></select>
  </span>
  <span class="ql-formats">
    <button class="ql-link" type="button"></button>
    <button class="ql-image" type="button"></button>
    <button class="ql-clean" type="button"></button>
  </span>
`

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

export const NotebookItemEditor = {
  mounted() {
    this.heartbeatTimer = null
    this.pushChangeTimer = null
    this.hasLock = false
    this.lastServerText = this.el.dataset.text || ""

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

    this.editorHtml = () => {
      const html = this.quill.root.innerHTML
      return html === "<p><br></p>" ? "" : html
    }

    this.editorPlainText = () => this.quill.getText().replace(/\n$/, "")

    this.setEditorHtml = html => {
      if (html === "") {
        this.quill.setText("", "silent")
        return
      }

      this.quill.clipboard.dangerouslyPasteHTML(html, "silent")
    }

    this.pushEditorChange = () => {
      this.pushEvent("edit_node_text", {
        ...this.itemTarget(),
        text: this.editorHtml(),
        plain_text: this.editorPlainText(),
      })
    }

    this.queueEditorChange = () => {
      if (this.pushChangeTimer) {
        clearTimeout(this.pushChangeTimer)
      }

      this.pushChangeTimer = setTimeout(() => {
        this.pushEditorChange()
      }, 120)
    }

    this.pushKeyboardEvent = eventName => {
      this.pushEvent(eventName, {
        ...this.itemTarget(),
        text: this.editorHtml(),
        plain_text: this.editorPlainText(),
      })
    }

    this.editorRange = () => this.quill.getSelection()

    this.hasMultipleLines = () => this.editorPlainText().includes("\n")

    this.cursorAtFront = range => range && range.length === 0 && range.index === 0

    this.cursorAtEnd = range => {
      if (!range || range.length !== 0) {
        return false
      }

      return range.index === this.quill.getLength() - 1
    }

    this.hasChildInDom = () => {
      const itemRoot = this.el.closest("li[data-notebook-path]")
      return Boolean(itemRoot?.querySelector(':scope > ul > li[data-notebook-path]'))
    }

    this.handleStructuralEnter = ({shiftKey}) => {
      const range = this.editorRange()
      const plainText = this.editorPlainText()
      const isEmpty = plainText === ""
      const hasMultipleLines = this.hasMultipleLines()
      const atFront = this.cursorAtFront(range)
      const atEnd = this.cursorAtEnd(range)
      const inMiddle = !isEmpty && !atFront && !atEnd

      if (isEmpty) {
        if (shiftKey) {
          return true
        }

        this.pushKeyboardEvent("item_empty_enter")
        return false
      }

      if (shiftKey) {
        if (hasMultipleLines) {
          if (atFront) {
            this.pushKeyboardEvent("item_insert_above")
            return false
          }

          this.pushKeyboardEvent("item_insert_child_first")
          return false
        }

        if (inMiddle) {
          this.pushKeyboardEvent("item_insert_child_first")
          return false
        }

        return true
      }

      if (hasMultipleLines || inMiddle) {
        return true
      }

      if (atFront) {
        this.pushKeyboardEvent("item_insert_above")
        return false
      }

      if (atEnd) {
        this.pushKeyboardEvent("item_insert_child_first")
        return false
      }

      return true
    }

    this.setToolbarVisible = visible => {
      this.toolbarEl.classList.toggle("hidden", !visible)
    }

    this.activateEditor = () => {
      if (!this.hasLock) {
        this.pushEvent("item_lock_acquire", this.itemTarget())
        this.hasLock = true
      }

      this.startHeartbeat()
      this.setToolbarVisible(true)
    }

    this.deactivateEditor = () => {
      this.stopHeartbeat()

      if (this.hasLock) {
        this.pushEvent("item_lock_release", this.itemTarget())
        this.hasLock = false
      }

      this.setToolbarVisible(false)
    }

    this.onFocus = () => {
      this.activateEditor()
    }

    this.onBlur = event => {
      const nextTarget = event.relatedTarget

      if (nextTarget && this.isEditorUiTarget(nextTarget)) {
        return
      }

      this.deactivateEditor()
    }

    this.onToolbarFocusIn = () => {
      this.activateEditor()
    }

    this.onToolbarFocusOut = event => {
      const nextTarget = event.relatedTarget

      if (nextTarget && this.isEditorUiTarget(nextTarget)) {
        return
      }

      this.deactivateEditor()
    }

    this.toolbarEl = document.createElement("div")
    this.toolbarEl.className = "ql-toolbar ql-snow notebook-editor-toolbar"
    this.toolbarEl.innerHTML = notebookToolbarMarkup()

    this.editorEl = document.createElement("div")
    this.editorEl.className = "ql-editor-host notebook-editor-surface"

    this.el.replaceChildren(this.editorEl, this.toolbarEl)

    this.applyDisabledState = () => {
      const disabled = this.el.dataset.disabled === "true"
      this.quill.enable(!disabled)

      this.toolbarEl.querySelectorAll("button, select").forEach(control => {
        control.disabled = disabled
      })

      this.toolbarEl.classList.toggle("opacity-55", disabled)
      this.toolbarEl.classList.toggle("pointer-events-none", disabled)
    }

    this.quill = new Quill(this.editorEl, {
      theme: "snow",
      modules: {
        toolbar: {
          container: this.toolbarEl,
        },
      },
      placeholder: this.el.dataset.placeholder || "Write item...",
    })

    this.tooltip = this.quill.theme?.tooltip || null

    this.findImageBlotAt = index => {
      if (typeof index !== "number" || index < 0) {
        return null
      }

      const [blot] = this.quill.getLeaf(index)

      if (blot?.statics?.blotName === "image") {
        return blot
      }

      return null
    }

    this.findActiveImageBlot = range => {
      if (!range) {
        return null
      }

      return (
        this.findImageBlotAt(range.index) ||
        (range.length === 0 && range.index > 0 ? this.findImageBlotAt(range.index - 1) : null)
      )
    }

    this.findInsertedImageNode = (insertIndex, imageUrl) => {
      const nearbyBlot =
        this.findImageBlotAt(insertIndex) ||
        this.findImageBlotAt(insertIndex + 1) ||
        this.findImageBlotAt(Math.max(insertIndex - 1, 0))

      if (nearbyBlot?.domNode) {
        return nearbyBlot.domNode
      }

      const matchingImages = [...this.quill.root.querySelectorAll("img")].filter(
        img => img.getAttribute("src") === imageUrl
      )

      return matchingImages.at(-1) || null
    }

    this.findInsertedImageBlot = (insertIndex, imageUrl) => {
      const nearbyBlot =
        this.findImageBlotAt(insertIndex) ||
        this.findImageBlotAt(insertIndex + 1) ||
        this.findImageBlotAt(Math.max(insertIndex - 1, 0))

      if (nearbyBlot) {
        return nearbyBlot
      }

      const insertedNode = this.findInsertedImageNode(insertIndex, imageUrl)
      return insertedNode ? Quill.find(insertedNode) : null
    }

    this.imagePositionValue = imageNode => {
      const positionClass = NOTEBOOK_IMAGE_POSITION_CLASSES.find(className =>
        imageNode?.classList.contains(className)
      )

      return positionClass?.replace("notebook-image-", "") || "left"
    }

    this.sanitizeImageUrlInput = value => {
      const trimmedValue = value.trim()
      return /^(https?:\/\/|\/)/i.test(trimmedValue) ? trimmedValue : null
    }

    this.sanitizeImageDimensionInput = value => {
      const trimmedValue = value.trim()

      if (trimmedValue === "") {
        return ""
      }

      return /^\d{1,4}$/.test(trimmedValue) ? trimmedValue : null
    }

    this.applyImagePosition = (img, position) => {
      img.classList.remove(...NOTEBOOK_IMAGE_POSITION_CLASSES)
      img.classList.add(`notebook-image-${position}`)
    }

    this.positionFloatingElement = (element, referenceRect) => {
      if (!element || !referenceRect) {
        return
      }

      const hostRect = this.el.getBoundingClientRect()
      const left = referenceRect.left - hostRect.left
      const top = referenceRect.bottom - hostRect.top + 8

      element.style.left = `${left}px`
      element.style.top = `${top}px`

      const elementRect = element.getBoundingClientRect()

      if (elementRect.right > hostRect.right) {
        element.style.left = `${Math.max(0, left + (hostRect.right - elementRect.right))}px`
      }

      if (elementRect.left < hostRect.left) {
        element.style.left = `${Math.max(0, left + (hostRect.left - elementRect.left))}px`
      }
    }

    this.positionTooltipToStart = reference => {
      if (!this.tooltip || !reference) {
        return
      }

      this.originalTooltipPosition?.(reference)

      const desiredLeft = reference.left
      this.tooltip.root.style.left = `${desiredLeft}px`

      const containerBounds = this.tooltip.boundsContainer.getBoundingClientRect()
      const rootBounds = this.tooltip.root.getBoundingClientRect()

      if (rootBounds.right > containerBounds.right) {
        this.tooltip.root.style.left = `${desiredLeft + (containerBounds.right - rootBounds.right)}px`
      }

      if (rootBounds.left < containerBounds.left) {
        this.tooltip.root.style.left = `${desiredLeft + (containerBounds.left - rootBounds.left)}px`
      }
    }

    this.tooltipReferenceForMode = reference => {
      if (!this.tooltip) {
        return reference
      }

      const mode = this.tooltip.root.getAttribute("data-mode")

      if (mode === "link" && this.tooltip.linkRange) {
        return this.quill.getBounds(this.tooltip.linkRange.index, this.tooltip.linkRange.length || 1)
      }

      return reference
    }

    this.hideImageTooltip = () => {
      this.imageEditingBlot = null
      this.tooltip.hide()
      this.tooltip.restoreFocus()
    }

    this.hideImageOptionsBubble = () => {
      this.selectedImageNode = null
      this.imageOptionsEl?.classList.add("hidden")
    }

    this.openImageLightbox = imageNode => {
      const imageUrl = imageNode?.getAttribute("src")

      if (!imageUrl || !this.imageLightboxEl) {
        return
      }

      this.lightboxImageEl.src = imageUrl
      this.lightboxImageEl.alt = imageNode.getAttribute("alt") || "Notebook image"
      this.imageLightboxEl.classList.remove("hidden")
      this.imageLightboxEl.setAttribute("aria-hidden", "false")
      document.body.classList.add("overflow-hidden")
    }

    this.closeImageLightbox = () => {
      if (!this.imageLightboxEl) {
        return
      }

      this.imageLightboxEl.classList.add("hidden")
      this.imageLightboxEl.setAttribute("aria-hidden", "true")
      this.lightboxImageEl.removeAttribute("src")
      document.body.classList.remove("overflow-hidden")
    }

    this.openImageOptionsBubble = imageNode => {
      if (!imageNode || !this.imageOptionsEl) {
        return
      }

      this.selectedImageNode = imageNode
      this.imageOptionsEl.classList.remove("hidden")
      this.positionFloatingElement(this.imageOptionsEl, imageNode.getBoundingClientRect())
    }

    this.repositionLinkTooltipToLinkStart = () => {
      if (!this.tooltip?.linkRange) {
        return
      }

      const linkReference = this.quill.getBounds(this.tooltip.linkRange.index, 1)
      this.positionTooltipToStart(linkReference)
    }

    this.openImageTooltipForBlot = imageBlot => {
      if (!this.tooltip) {
        return
      }

      const range = this.quill.getSelection(true)

      if (!range && !imageBlot) {
        return
      }

      window.requestAnimationFrame(() => {
        const imageNode = imageBlot?.domNode

        this.imageEditingBlot = imageBlot || null
        this.imageUrlInput.value = imageNode?.getAttribute("src") || ""
        this.imageWidthInput.value = imageNode?.getAttribute("width") || ""
        this.imageHeightInput.value = imageNode?.getAttribute("height") || ""
        this.imagePositionInput.value = this.imagePositionValue(imageNode)

        this.tooltip.root.classList.remove("ql-hidden")
        this.tooltip.root.classList.add("ql-editing")
        this.tooltip.root.setAttribute("data-mode", "image")
        this.hideImageOptionsBubble()

        const bounds =
          imageBlot
            ? this.quill.getBounds(this.quill.getIndex(imageBlot), 1)
            : this.quill.getBounds(range.index, range.length)

        this.positionTooltipToStart(bounds)

        this.imageUrlInput.focus()
        this.imageUrlInput.select()
      })
    }

    this.openImageTooltip = () => {
      this.openImageTooltipForBlot(null)
    }

    this.saveImageFromTooltip = () => {
      const imageUrl = this.sanitizeImageUrlInput(this.imageUrlInput.value)
      const width = this.sanitizeImageDimensionInput(this.imageWidthInput.value)
      const height = this.sanitizeImageDimensionInput(this.imageHeightInput.value)
      const position = ["left", "center", "right"].includes(this.imagePositionInput.value)
        ? this.imagePositionInput.value
        : "left"

      if (!imageUrl || width === null || height === null) {
        return
      }

      const selection = this.quill.getSelection(true)
      let insertIndex = selection?.index || 0

      if (this.imageEditingBlot) {
        insertIndex = this.quill.getIndex(this.imageEditingBlot)
        this.quill.deleteText(insertIndex, 1, "user")
      }

      this.quill.insertEmbed(insertIndex, "image", imageUrl, "user")

      const insertedNode = this.findInsertedImageNode(insertIndex, imageUrl)

      if (insertedNode) {
        const insertedBlot = this.findInsertedImageBlot(insertIndex, imageUrl)

        if (width) {
          insertedNode.setAttribute("width", width)
        } else {
          insertedNode.removeAttribute("width")
        }

        if (height) {
          insertedNode.setAttribute("height", height)
        } else {
          insertedNode.removeAttribute("height")
        }

        this.applyImagePosition(insertedNode, position)

        if (insertedBlot?.format) {
          insertedBlot.format("width", width || false)
          insertedBlot.format("height", height || false)
          insertedBlot.format("class", `notebook-image-${position}`)
        }
      }

      this.quill.update("user")
      this.quill.setSelection(insertIndex + 1, 0, "silent")
      this.hideImageTooltip()
      this.queueEditorChange()
    }

    this.quill.getModule("toolbar")?.addHandler("image", this.openImageTooltip)

    this.onEditorClick = event => {
      const imageNode = event.target.closest("img")

      if (!imageNode || !this.quill.root.contains(imageNode)) {
        this.hideImageOptionsBubble()
        return
      }

      event.preventDefault()
      this.activateEditor()
      this.openImageOptionsBubble(imageNode)
    }

    this.isEditorUiTarget = target => {
      if (!target) {
        return false
      }

      return (
        target === this.quill.root ||
        this.toolbarEl.contains(target) ||
        this.tooltip?.root?.contains(target) ||
        this.imageOptionsEl?.contains(target) ||
        this.imageLightboxEl?.contains(target) ||
        this.el.contains(target)
      )
    }

    this.closeTooltip = () => {
      if (!this.tooltip) {
        return
      }

      if (typeof this.tooltip.cancel === "function") {
        this.tooltip.cancel()
      } else if (typeof this.tooltip.hide === "function") {
        this.tooltip.hide()
      }
    }

    if (this.tooltip) {
      this.originalTooltipSave = this.tooltip.save?.bind(this.tooltip)
      this.originalTooltipCancel = this.tooltip.cancel?.bind(this.tooltip)
      this.originalTooltipPosition = this.tooltip.position?.bind(this.tooltip)

      this.tooltip.position = reference => {
        const anchoredReference = this.tooltipReferenceForMode(reference)
        const shift = this.originalTooltipPosition?.(anchoredReference)
        const mode = this.tooltip.root.getAttribute("data-mode")

        if (mode === "link" || mode === "image" || mode == null) {
          const desiredLeft = anchoredReference.left
          this.tooltip.root.style.left = `${desiredLeft}px`

          const containerBounds = this.tooltip.boundsContainer.getBoundingClientRect()
          const rootBounds = this.tooltip.root.getBoundingClientRect()

          if (rootBounds.right > containerBounds.right) {
            this.tooltip.root.style.left = `${desiredLeft + (containerBounds.right - rootBounds.right)}px`
          }

          if (rootBounds.left < containerBounds.left) {
            this.tooltip.root.style.left = `${desiredLeft + (containerBounds.left - rootBounds.left)}px`
          }
        }

        return shift
      }

      this.tooltip.save = () => {
        if (this.tooltip.root.getAttribute("data-mode") === "image") {
          this.saveImageFromTooltip()
          return
        }

        this.originalTooltipSave?.()
      }

      this.tooltip.cancel = () => {
        if (this.tooltip.root.getAttribute("data-mode") === "image") {
          this.hideImageTooltip()
          return
        }

        this.originalTooltipCancel?.()
      }
    }

    this.imageOptionsEl = document.createElement("div")
    this.imageOptionsEl.className = "notebook-image-options-bubble hidden"
    this.imageOptionsEl.innerHTML = `
      <div class="notebook-image-options-row">
        <button type="button" class="notebook-image-option-show">Show</button>
        <button type="button" class="notebook-image-option-edit">Edit</button>
      </div>
    `
    this.el.appendChild(this.imageOptionsEl)

    this.imageLightboxEl = document.createElement("div")
    this.imageLightboxEl.className = "notebook-image-lightbox hidden"
    this.imageLightboxEl.setAttribute("aria-hidden", "true")
    this.imageLightboxEl.innerHTML = `
      <button type="button" class="notebook-image-lightbox-close" aria-label="Close image viewer">Close</button>
      <div class="notebook-image-lightbox-backdrop"></div>
      <div class="notebook-image-lightbox-frame">
        <img class="notebook-image-lightbox-image" alt="">
      </div>
    `
    document.body.appendChild(this.imageLightboxEl)
    this.lightboxImageEl = this.imageLightboxEl.querySelector(".notebook-image-lightbox-image")

    this.imageShowButton = this.imageOptionsEl.querySelector(".notebook-image-option-show")
    this.imageEditButton = this.imageOptionsEl.querySelector(".notebook-image-option-edit")
    this.lightboxCloseButton = this.imageLightboxEl.querySelector(".notebook-image-lightbox-close")
    this.lightboxBackdrop = this.imageLightboxEl.querySelector(".notebook-image-lightbox-backdrop")

    this.onImageShowClick = event => {
      event.preventDefault()
      this.openImageLightbox(this.selectedImageNode)
    }

    this.onImageEditClick = event => {
      event.preventDefault()
      const imageBlot = this.selectedImageNode ? Quill.find(this.selectedImageNode) : null
      this.openImageTooltipForBlot(imageBlot)
    }

    this.onLightboxCloseClick = () => this.closeImageLightbox()

    this.imageShowButton.addEventListener("click", this.onImageShowClick)
    this.imageEditButton.addEventListener("click", this.onImageEditClick)
    this.lightboxCloseButton.addEventListener("click", this.onLightboxCloseClick)
    this.lightboxBackdrop.addEventListener("click", this.onLightboxCloseClick)

    if (this.tooltip?.root && !this.tooltip.root.querySelector(".ql-image-form")) {
      this.linkLabelEl = document.createElement("label")
      this.linkLabelEl.className = "ql-link-field"
      this.linkLabelEl.innerHTML = `
        <span>URL</span>
      `
      this.tooltip.root.insertBefore(this.linkLabelEl, this.tooltip.root.querySelector('input[type="text"]'))

      this.imageFormEl = document.createElement("div")
      this.imageFormEl.className = "ql-image-form"
      this.imageFormEl.innerHTML = `
        <label class="ql-image-field">
          <span>Image URL</span>
          <input class="ql-image-url" type="url" placeholder="https://example.com/image.png">
        </label>
        <div class="ql-image-meta-grid">
          <label class="ql-image-field">
            <span>Width</span>
            <input class="ql-image-width" type="text" inputmode="numeric" placeholder="auto">
          </label>
          <label class="ql-image-field">
            <span>Height</span>
            <input class="ql-image-height" type="text" inputmode="numeric" placeholder="auto">
          </label>
          <label class="ql-image-field ql-image-position-field">
            <span>Position</span>
            <select class="ql-image-position">
              <option value="left">Left</option>
              <option value="center">Center</option>
              <option value="right">Right</option>
            </select>
          </label>
        </div>
        <p class="ql-image-help">Leave width or height empty to keep the image ratio automatic.</p>
      `

      this.tooltip.root.appendChild(this.imageFormEl)
    }

    this.imageUrlInput = this.tooltip?.root?.querySelector(".ql-image-url") || null
    this.imageWidthInput = this.tooltip?.root?.querySelector(".ql-image-width") || null
    this.imageHeightInput = this.tooltip?.root?.querySelector(".ql-image-height") || null
    this.imagePositionInput = this.tooltip?.root?.querySelector(".ql-image-position") || null
    this.tooltipActionEl = this.tooltip?.root?.querySelector(".ql-action") || null

    this.onImageTooltipKeydown = event => {
      if (this.tooltip?.root?.getAttribute("data-mode") !== "image") {
        return
      }

      if (event.key === "Enter") {
        event.preventDefault()
        this.saveImageFromTooltip()
      } else if (event.key === "Escape") {
        event.preventDefault()
        this.hideImageTooltip()
      }
    }

    ;[this.imageUrlInput, this.imageWidthInput, this.imageHeightInput, this.imagePositionInput]
      .filter(Boolean)
      .forEach(input => input.addEventListener("keydown", this.onImageTooltipKeydown))

    this.onTooltipActionClick = () => {
      window.requestAnimationFrame(() => {
        if (this.tooltip?.root?.getAttribute("data-mode") === "link") {
          this.repositionLinkTooltipToLinkStart()
        }
      })
    }

    this.tooltipActionEl?.addEventListener("click", this.onTooltipActionClick)

    if (this.tooltip?.root && !this.tooltip.root.querySelector(".ql-cancel")) {
      this.cancelLinkEl = document.createElement("button")
      this.cancelLinkEl.type = "button"
      this.cancelLinkEl.className = "ql-cancel"
      this.cancelLinkEl.textContent = "Cancel"
      this.cancelLinkEl.addEventListener("click", event => {
        event.preventDefault()
        this.closeTooltip()
      })
      this.tooltip.root.appendChild(this.cancelLinkEl)
    }

    this.onDocumentPointerDown = event => {
      if (this.imageLightboxEl && !this.imageLightboxEl.classList.contains("hidden")) {
        return
      }

      if (!this.tooltip || this.tooltip.root.classList.contains("ql-hidden")) {
        if (this.imageOptionsEl && !this.imageOptionsEl.contains(event.target) && !event.target.closest("img")) {
          this.hideImageOptionsBubble()
        }
      }

      if (!this.tooltip || this.tooltip.root.classList.contains("ql-hidden")) {
        return
      }

      if (this.isEditorUiTarget(event.target)) {
        return
      }

      this.closeTooltip()
      this.deactivateEditor()
    }

    this.onDocumentKeydown = event => {
      if (event.key === "Escape") {
        this.closeImageLightbox()
        this.hideImageOptionsBubble()
      }
    }

    this.setEditorHtml(this.lastServerText)

    this.quill.on("text-change", (_delta, _oldDelta, source) => {
      if (source !== "user") {
        return
      }

      this.queueEditorChange()
    })

    this.onEditorKeydown = event => {
      if (event.defaultPrevented) {
        return
      }

      if (event.key === "Tab") {
        event.preventDefault()
        event.stopPropagation()

        if (event.shiftKey) {
          this.pushKeyboardEvent("item_outdent")
        } else {
          this.pushKeyboardEvent("item_indent")
        }

        return
      }

      if (event.key === "Enter") {
        const allowDefault = this.handleStructuralEnter(event)

        if (!allowDefault) {
          event.preventDefault()
          event.stopPropagation()
        }

        return
      }

      if (event.key === "ArrowUp") {
        const range = this.editorRange()

        if (this.cursorAtFront(range)) {
          event.preventDefault()
          event.stopPropagation()
          this.pushKeyboardEvent("item_focus_up")
        }

        return
      }

      if (event.key === "ArrowDown") {
        const range = this.editorRange()

        if (this.cursorAtEnd(range) || this.editorPlainText() === "") {
          event.preventDefault()
          event.stopPropagation()
          this.pushKeyboardEvent("item_focus_down")
        }

        return
      }

      if ((event.key === "Backspace" || event.key === "Delete") && this.editorPlainText() === "") {
        if (this.hasChildInDom()) {
          return
        }

        event.preventDefault()
        event.stopPropagation()
        this.quill.blur()
        this.pushKeyboardEvent(
          event.key === "Backspace" ? "item_delete_empty_backward" : "item_delete_empty_forward"
        )
      }
    }

    this.quill.keyboard.addBinding({key: 8}, () => {
      if (this.editorPlainText() !== "") {
        return true
      }

      return false
    })

    this.quill.keyboard.addBinding({key: 46}, () => {
      if (this.editorPlainText() !== "") {
        return true
      }

      return false
    })

    this.handleEvent("focus-item", ({path, page_id}) => {
      if (this.el.dataset.path === path && this.el.dataset.pageId === String(page_id)) {
        this.quill.focus()
        const len = this.quill.getLength() - 1
        this.quill.setSelection(Math.max(len, 0), 0, "silent")
      }
    })

    this.quill.root.addEventListener("focus", this.onFocus)
    this.quill.root.addEventListener("blur", this.onBlur)
    this.quill.root.addEventListener("click", this.onEditorClick)
    this.quill.root.addEventListener("keydown", this.onEditorKeydown, true)
    this.toolbarEl.addEventListener("focusin", this.onToolbarFocusIn)
    this.toolbarEl.addEventListener("focusout", this.onToolbarFocusOut)
    document.addEventListener("pointerdown", this.onDocumentPointerDown)
    document.addEventListener("keydown", this.onDocumentKeydown)

    this.applyDisabledState()
    this.setToolbarVisible(false)
  },

  updated() {
    const latestServerText = this.el.dataset.text || ""
    const activeElement = document.activeElement
    const editorFocused =
      this.quill && this.isEditorUiTarget(activeElement)

    if (!editorFocused && latestServerText !== this.lastServerText) {
      this.setEditorHtml(latestServerText)
      this.lastServerText = latestServerText
    }

    this.applyDisabledState()

    if (this.el.dataset.disabled === "true" && editorFocused) {
      this.quill.blur()
    }
  },

  destroyed() {
    this.stopHeartbeat()

    if (this.pushChangeTimer) {
      clearTimeout(this.pushChangeTimer)
      this.pushChangeTimer = null
    }

    if (this.hasLock) {
      this.pushEvent("item_lock_release", this.itemTarget())
      this.hasLock = false
    }

    this.setToolbarVisible(false)

    if (this.quill) {
      this.quill.root.removeEventListener("focus", this.onFocus)
      this.quill.root.removeEventListener("blur", this.onBlur)
      this.quill.root.removeEventListener("click", this.onEditorClick)
      this.quill.root.removeEventListener("keydown", this.onEditorKeydown, true)
      this.toolbarEl.removeEventListener("focusin", this.onToolbarFocusIn)
      this.toolbarEl.removeEventListener("focusout", this.onToolbarFocusOut)
      document.removeEventListener("pointerdown", this.onDocumentPointerDown)
      document.removeEventListener("keydown", this.onDocumentKeydown)
      ;[this.imageUrlInput, this.imageWidthInput, this.imageHeightInput, this.imagePositionInput]
        .filter(Boolean)
        .forEach(input => input.removeEventListener("keydown", this.onImageTooltipKeydown))
      this.tooltipActionEl?.removeEventListener("click", this.onTooltipActionClick)
      this.imageShowButton?.removeEventListener("click", this.onImageShowClick)
      this.imageEditButton?.removeEventListener("click", this.onImageEditClick)
      this.lightboxCloseButton?.removeEventListener("click", this.onLightboxCloseClick)
      this.lightboxBackdrop?.removeEventListener("click", this.onLightboxCloseClick)
      this.imageOptionsEl?.remove()
      this.imageLightboxEl?.remove()
      document.body.classList.remove("overflow-hidden")
      this.cancelLinkEl?.remove()
      this.quill = null
    }
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
  },

  updated() {
    const sameItem =
      this.previousNodeId === this.el.dataset.nodeId && this.previousPath === this.el.dataset.path

    if (!this.wasOpen || !sameItem) {
      return
    }

    this.el.open = true
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

    this.copyNoticeTimer = null
    this.copyNoticeEl = null

    this.copyTextToClipboard = async text => {
      if (navigator.clipboard?.writeText && window.isSecureContext) {
        await navigator.clipboard.writeText(text)
        return
      }

      const textarea = document.createElement("textarea")
      textarea.value = text
      textarea.setAttribute("readonly", "readonly")
      textarea.style.position = "fixed"
      textarea.style.top = "-9999px"
      textarea.style.left = "-9999px"
      document.body.appendChild(textarea)
      textarea.focus()
      textarea.select()
      document.execCommand("copy")
      textarea.remove()
    }

    this.closeOpenMenus = () => {
      document.querySelectorAll("details[open]").forEach(details => {
        details.open = false
      })
    }

    this.showCopyNotice = message => {
      if (!message) {
        return
      }

      if (!this.copyNoticeEl) {
        this.copyNoticeEl = document.createElement("div")
        this.copyNoticeEl.className = [
          "pointer-events-none fixed bottom-4 left-1/2 z-[70] -translate-x-1/2 rounded-xl",
          "border border-success/25 bg-success px-3 py-2 text-sm font-medium text-success-content",
          "shadow-lg transition-opacity duration-200",
        ].join(" ")
        document.body.appendChild(this.copyNoticeEl)
      }

      this.copyNoticeEl.textContent = message
      this.copyNoticeEl.style.opacity = "1"

      if (this.copyNoticeTimer) {
        clearTimeout(this.copyNoticeTimer)
      }

      this.copyNoticeTimer = setTimeout(() => {
        if (this.copyNoticeEl) {
          this.copyNoticeEl.style.opacity = "0"
        }
      }, 1400)
    }

    this.flashCopyButton = pageId => {
      if (!pageId) {
        return
      }

      const button = document.getElementById(`copy-page-items-${pageId}`)

      if (!button) {
        return
      }

      const originalHtml = button.innerHTML
      button.innerHTML = '<span class="hero-check size-3.5"></span> Copied!'
      button.disabled = true

      window.setTimeout(() => {
        button.innerHTML = originalHtml
        button.disabled = false
      }, 1200)
    }

    this.handleEvent("copy-text-to-clipboard", async ({text, success_message, page_id}) => {
      try {
        await this.copyTextToClipboard(text || "")
        this.closeOpenMenus()
        this.flashCopyButton(page_id)
        this.showCopyNotice(success_message || "Copied")
      } catch (_error) {
        this.showCopyNotice("Couldn’t copy to clipboard automatically")
      }
    })

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

    if (this.copyNoticeTimer) {
      clearTimeout(this.copyNoticeTimer)
      this.copyNoticeTimer = null
    }

    this.copyNoticeEl?.remove()
    this.copyNoticeEl = null
  },
}
