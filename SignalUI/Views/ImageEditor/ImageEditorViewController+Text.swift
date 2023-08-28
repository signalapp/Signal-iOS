//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

// MARK: - Sticker

extension ImageEditorViewController {
    func selectStickerItem(_ stickerItem: ImageEditorStickerItem) {
        mode = .sticker
        imageEditorView.selectedTransformableItemID = stickerItem.itemId
        model.append(item: stickerItem)
    }
}

// MARK: - Text

extension ImageEditorViewController {

    func selectTextItem(_ textItem: ImageEditorTextItem, isNewItem: Bool, startEditing: Bool) {
        mode = .text
        currentTextItem = (textItem, isNewItem)
        imageEditorView.selectedTransformableItemID = textItem.itemId
        if startEditing && isViewLoaded && view.window != nil {
            beginTextEditing()
        } else {
            startEditingTextOnViewAppear = startEditing
        }
    }

    var canBeginTextEditingOnViewAppear: Bool {
        guard mode == .text else {
            return false
        }
        return currentTextItem != nil
    }

    private func initializeTextUIIfNecessary() {
        guard !textUIInitialized else { return }

        let toolbarSize = textViewAccessoryToolbar.systemLayoutSizeFitting(CGSize(width: view.width, height: .greatestFiniteMagnitude),
                                                                           withHorizontalFittingPriority: .required,
                                                                           verticalFittingPriority: .fittingSizeLevel)
        textViewAccessoryToolbar.bounds.size = toolbarSize
        textView.inputAccessoryView = textViewAccessoryToolbar

        // Background view is necessary because animations of textViewContainer.frame
        // don't match animations of the keyboard and non-dimmed area was showing
        // in between the bottom edge of textViewContainer and the top of keyboard.
        let textContainerBackground = UIView()
        textContainerBackground.backgroundColor = .ows_blackAlpha40
        textViewContainer.addSubview(textContainerBackground)
        textContainerBackground.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        textContainerBackground.autoPinEdge(toSuperviewEdge: .bottom, withInset: -300)

        textViewBackgroundView.layer.cornerRadius = 8
        textViewWrapperView.addSubview(textViewBackgroundView)
        textViewWrapperView.addSubview(textView)
        textViewBackgroundView.autoSetDimension(.width, toSize: 36, relation: .greaterThanOrEqual)
        textViewBackgroundView.autoSetDimension(.height, toSize: 36, relation: .greaterThanOrEqual)
        textViewBackgroundView.autoPinWidthToSuperviewMargins(relation: .lessThanOrEqual)
        textViewBackgroundView.autoPinHeightToSuperviewMargins(relation: .lessThanOrEqual)
        textViewBackgroundView.autoCenterInSuperview()
        // These inset values provide the best visual match with CATextLayer's bounds when background color is set.
        textView.autoPinEdges(toEdgesOf: textViewBackgroundView, with: UIEdgeInsets(top: -6, left: 6, bottom: -7, right: 6))

        textViewContainer.addSubview(textViewWrapperView)
        textViewWrapperView.autoVCenterInSuperview()
        textViewWrapperView.autoPinWidthToSuperviewMargins()
        textViewWrapperView.autoPinHeightToSuperviewMargins(relation: .lessThanOrEqual)

        view.addSubview(textViewContainer)
        textViewContainer.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        textViewContainerBottomConstraint = textViewContainer.autoPinEdge(toSuperviewEdge: .bottom)

        textViewContainer.addGestureRecognizer(ImageEditorPinchGestureRecognizer(target: self, action: #selector(handleTextPinchGesture(_:))))
        textViewContainer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapDimmerView(_:))))

        UIView.performWithoutAnimation {
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }

        textUIInitialized = true
    }

    func updateTextControlsVisibility() {
        // Nothing to update
    }

    /**
     * Load all UITextView's attributes from ImageEditorTextItem.
     * This method needs to be called when text item editing is about to begin.
     */
    private func updateTextViewAttributes(using textItem: ImageEditorTextItem) {
        textView.updateWith(textForegroundColor: textItem.textForegroundColor,
                            font: textItem.font,
                            textAlignment: .center,
                            textDecorationColor: textItem.textDecorationColor,
                            decorationStyle: textItem.decorationStyle)
        textViewBackgroundView.backgroundColor = textItem.textBackgroundColor
    }

    // Update UITextView to use style (font, color, decoration) as selected in provided TextToolbar.
    // This method needs to be called whenever user changes text styling while UITextView is active
    // in order to reflect the changes right away.
    func updateTextViewAttributes(using textToolbar: TextStylingToolbar) {
        let fontPointSize = textView.font?.pointSize ?? ImageEditorTextItem.defaultFontSize
        textView.update(using: textToolbar, fontPointSize: fontPointSize)
        textViewBackgroundView.backgroundColor = textToolbar.textBackgroundColor
    }

    func updateTextViewContainerBottomLayoutConstraint(forKeyboardFrame keyboardFrame: CGRect) {
        guard mode == .text, let textViewContainerBottomConstraint else {
            return
        }
        let keyboardHeight: CGFloat
        if keyboardFrame.width >= view.bounds.width {
            keyboardHeight = keyboardFrame.height
        } else {
            keyboardHeight = 0
        }
        textViewContainerBottomConstraint.constant = -keyboardHeight
    }

    func updateTextUIVisibility() {
        switch mode {
        case .text:
            initializeTextUIIfNecessary()
            fallthrough
        case .sticker:
            imageEditorView.delegate = self
        case .draw, .blur:
            guard textUIInitialized else { break }
            imageEditorView.selectedTransformableItemID = nil
        }
    }

    func beginTextEditing() {
        guard let textItem = currentTextItem?.textItem else { return }

        bottomBar.setIsHidden(true, animated: true)

        textViewAccessoryToolbar.currentColorPickerValue = textItem.color
        textViewAccessoryToolbar.textStyle = textItem.textStyle
        textViewAccessoryToolbar.decorationStyle = textItem.decorationStyle

        textView.text = textItem.text
        updateTextViewAttributes(using: textItem)

        imageEditorView.canvasView.hiddenItemId = textItem.itemId

        UIView.animate(withDuration: 0.2) {
            self.textViewContainer.alpha = 1
        }
        textView.becomeFirstResponder()
    }

    func finishTextEditing(discardEdits: Bool = false) {
        guard textUIInitialized else { return }
        guard textView.isFirstResponder else { return }

        discardTextEditsOnEditingEnd = discardEdits

        textView.acceptAutocorrectSuggestion()
        textView.resignFirstResponder()
    }

    private func applyTextEdits() {
        guard let currentTextItem else { return }

        var textItem = currentTextItem.textItem

        // Update text's width.
        let view = imageEditorView.gestureReferenceView
        let viewBounds = view.bounds
        let imageFrame = ImageEditorCanvasView.imageFrame(forViewSize: viewBounds.size,
                                                          imageSize: model.srcImageSizePixels,
                                                          transform: model.currentTransform())
        // 12 is the sum of horizontal insets around textView as set in `initializeTextUIIfNecessary`.
        let unitWidth = (textViewWrapperView.width - 12) / imageFrame.width
        textItem = textItem.copy(unitWidth: unitWidth)

        // Ensure continuity of the new text item's location with its apparent location in this text editor.
        if currentTextItem.isNewItem {
            let locationInView = view.convert(textView.bounds.center, from: textView).clamp(view.bounds)
            let textCenterImageUnit = ImageEditorCanvasView.locationImageUnit(forLocationInView: locationInView,
                                                                              viewBounds: viewBounds,
                                                                              model: model,
                                                                              transform: model.currentTransform())
            textItem = textItem.copy(unitCenter: textCenterImageUnit)
        }

        // Update font size.
        if let textViewFont = textView.font {
            textItem = textItem.copy(fontSize: textViewFont.pointSize)
        }

        // Update text and decoration style.
        textItem = textItem.copy(
            textStyle: textViewAccessoryToolbar.textStyle,
            decorationStyle: textViewAccessoryToolbar.decorationStyle
        )

        // Deleting all text results in text object being deleted.
        guard let text = textView.text?.ows_stripped(), !text.isEmpty else {
            if model.has(itemForId: textItem.itemId) {
                model.remove(item: textItem)
            }
            return
        }

        // Update text.
        textItem = textItem.copy(withText: text, color: textViewAccessoryToolbar.currentColorPickerValue)

        guard currentTextItem.textItem != textItem else {
            // No changes were made.  Cancel to avoid dirtying the undo stack.
            return
        }

        // Finally - update model with modified text item.
        if model.has(itemForId: textItem.itemId) {
            model.replace(item: textItem, suppressUndo: false)
        } else {
            model.append(item: textItem)
        }

        imageEditorView.selectedTransformableItemID = textItem.itemId
    }

    @objc
    private func handleTextPinchGesture(_ gestureRecognizer: ImageEditorPinchGestureRecognizer) {
        AssertIsOnMainThread()

        guard mode == .text else {
            owsFailDebug("Incorrect mode [\(mode)]")
            return
        }

        guard let textViewFont = textView.font else {
            owsFailDebug("Text View font is nil")
            return
        }

        switch gestureRecognizer.state {
        case .began:
            pinchFontSizeStart = textViewFont.pointSize

        case .changed, .ended:
            var pointSize = pinchFontSizeStart
            if gestureRecognizer.pinchStateLast.distance > 0 {
                pointSize *= gestureRecognizer.pinchStateLast.distance / gestureRecognizer.pinchStateStart.distance
            }
            textView.font = textViewFont.withSize(pointSize.clamp(12, 64))

        default:
            break
        }
    }

    @objc
    private func didTapDimmerView(_ gestureRecognizer: UITapGestureRecognizer) {
        finishTextEditing()
    }

    @objc
    func didTapTextStyleButton(sender: UIButton) {
        let textStyle = textViewAccessoryToolbar.textStyle.next()
        textViewAccessoryToolbar.textStyle = textStyle
        updateTextViewAttributes(using: textViewAccessoryToolbar)
    }

    @objc
    func didTapDecorationStyleButton(sender: UIButton) {
        var decorationStyle = textViewAccessoryToolbar.decorationStyle.next()
        if decorationStyle == .outline {
            decorationStyle = .none
        }
        textViewAccessoryToolbar.decorationStyle = decorationStyle
        updateTextViewAttributes(using: textViewAccessoryToolbar)
    }

    @objc
    func didTapTextEditingDoneButton(sender: UIButton) {
        finishTextEditing()
    }
}

// MARK: - UITextViewDelegate

extension ImageEditorViewController: UITextViewDelegate {

    func textViewDidBeginEditing(_ textView: UITextView) {
        // Reset each time user starts editing text.
        discardTextEditsOnEditingEnd = false
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        bottomBar.setIsHidden(false, animated: true)

        // Save changes to the model unless we were told not to (eg when dismissing screen).
        if !discardTextEditsOnEditingEnd {
            applyTextEdits()
        }

        // Existing text is made hidden on the canvas while user is editing.
        // This is the time to make it visible.
        UIView.animate(withDuration: 0.2) {
            self.imageEditorView.canvasView.hiddenItemId = nil
            self.textViewContainer.alpha = 0
        }

        currentTextItem = nil
    }
}

// MARK: - ImageEditorViewDelegate

extension ImageEditorViewController: ImageEditorViewDelegate {

    func imageEditorView(_ imageEditorView: ImageEditorView, didRequestAddTextItem textItem: ImageEditorTextItem) {
        // No adding text via tap on image in this view controller.
        // Instead, tap on empty space deselects any selected text object
        // and switches the editor back to "draw" mode via `imageEditorViewDidUpdateSelection()`.
    }

    func imageEditorView(_ imageEditorView: ImageEditorView, didTapTextItem textItem: ImageEditorTextItem) {
        owsAssertDebug(imageEditorView.selectedTransformableItemID == textItem.itemId)
        currentTextItem = (textItem, false)
        beginTextEditing()
    }

    func imageEditorView(_ imageEditorView: ImageEditorView, didMoveTextItem textItem: ImageEditorTextItem) {

    }

    func imageEditorViewDidUpdateSelection(_ imageEditorView: ImageEditorView) {
        switch imageEditorView.selectedTransformableItemID {
        case .some(let selectedTransformableItemID):
            let selectedItem = model.item(forId: selectedTransformableItemID)
            if let textItem = selectedItem as? ImageEditorTextItem {
                mode = .text
                textViewAccessoryToolbar.currentColorPickerValue = textItem.color
                textViewAccessoryToolbar.textStyle = textItem.textStyle
                textViewAccessoryToolbar.decorationStyle = textItem.decorationStyle
            } else if selectedItem is ImageEditorStickerItem {
                mode = .sticker
            } else {
                fallthrough
            }
        case .none:
            mode = .draw
        }

        updateTextUIVisibility()
    }

    func imageEditorDidRequestToolbarVisibilityUpdate(_ imageEditorView: ImageEditorView) {
        updateControlsVisibility()
    }
}
