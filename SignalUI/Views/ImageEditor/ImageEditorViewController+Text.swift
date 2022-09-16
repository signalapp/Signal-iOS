//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

// MARK: - Text

extension ImageEditorViewController {

    func selectTextItem(_ textItem: ImageEditorTextItem, isNewItem: Bool, startEditing: Bool) {
        mode = .text
        currentTextItem = (textItem, isNewItem)
        imageEditorView.selectedTextItemId = textItem.itemId
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

        imageEditorView.delegate = self

        let toolbarSize = textViewAccessoryToolbar.systemLayoutSizeFitting(CGSize(width: view.width, height: .greatestFiniteMagnitude),
                                                                           withHorizontalFittingPriority: .required,
                                                                           verticalFittingPriority: .fittingSizeLevel)
        textViewAccessoryToolbar.bounds.size = toolbarSize
        textView.inputAccessoryView = textViewAccessoryToolbar

        view.addSubview(textToolbar)
        textToolbar.autoPinWidthToSuperview()
        textToolbar.autoPinEdge(.bottom, to: .top, of: bottomBar)

        // Background view is necessary because animations of textViewContainer.frame
        // don't match animations of the keyboard and non-dimmed area was showing
        // in between the bottom edge of textViewContainer and the top of keyboard.
        let textContainerBackground = UIView()
        textContainerBackground.backgroundColor = .ows_blackAlpha40
        textViewContainer.addSubview(textContainerBackground)
        textContainerBackground.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        textContainerBackground.autoPinEdge(toSuperviewEdge: .bottom, withInset: -300)

        textViewContainer.addSubview(textView)
        textView.autoVCenterInSuperview()
        textView.autoPinWidthToSuperviewMargins()
        textView.autoPinHeightToSuperviewMargins(relation: .lessThanOrEqual)
        textView.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true

        view.addSubview(textViewContainer)
        textViewContainer.autoPinEdge(toSuperviewEdge: .top)
        textViewContainer.autoPinWidthToSuperview()
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            autoPinView(toBottomOfViewControllerOrKeyboard: textViewContainer, avoidNotch: false)
        }
        textViewContainer.autoPinEdge(.bottom, to: .top, of: textToolbar, withOffset: 0, relation: .lessThanOrEqual)

        textViewContainer.addGestureRecognizer(ImageEditorPinchGestureRecognizer(target: self, action: #selector(handleTextPinchGesture(_:))))
        textViewContainer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapDimmerView(_:))))

        UIView.performWithoutAnimation {
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }

        textUIInitialized = true
    }

    func updateTextControlsVisibility() {
        textToolbar.alpha = topBar.alpha
    }

    /**
     * Load all UITextView's attributes from ImageEditorTextItem.
     * This method needs to be called when text item editing is about to begin.
     */
    func updateTextViewAttributes(using textItem: ImageEditorTextItem) {
        textView.update(withColor: textItem.color.color, font: textItem.font, decorationStyle: textItem.decorationStyle)
    }

    // Update UITextView to use style (font, color, decoration) as selected in provided TextToolbar.
    // This method needs to be called whenever user changes text styling while UITextView is active
    // in order to reflect the changes right away.
    func updateTextViewAttributes(using textToolbar: TextStylingToolbar) {
        let fontPointSize = textView.font?.pointSize ?? ImageEditorTextItem.defaultFontSize
        textView.update(using: textToolbar, fontPointSize: fontPointSize)
    }

    override func updateBottomLayoutConstraint(fromInset before: CGFloat, toInset after: CGFloat) {
        guard mode == .text, textUIInitialized else {
            super.updateBottomLayoutConstraint(fromInset: before, toInset: after)
            return
        }

        let accessoryViewHeight = textViewAccessoryToolbar.height
        super.updateBottomLayoutConstraint(fromInset: before, toInset: after - accessoryViewHeight)

        let onScreenKeyboardVisible = after > 150
        textViewAccessoryToolbar.alpha = onScreenKeyboardVisible ? 1 : 0
    }

    func updateTextUIVisibility() {
        let isInTextMode = mode == .text
        if isInTextMode {
            initializeTextUIIfNecessary()
        } else {
            guard textUIInitialized else { return }
        }

        if !isInTextMode {
            imageEditorView.selectedTextItemId = nil
        }

        let textToolBarHidden = imageEditorView.selectedTextItemId == nil && !textView.isFirstResponder
        textToolbar.isHidden = !isInTextMode || textToolBarHidden
    }

    func beginTextEditing() {
        guard let textItem = currentTextItem?.textItem else { return }

        textToolbar.colorPickerView.selectedValue = textItem.color
        textViewAccessoryToolbar.colorPickerView.selectedValue = textItem.color

        textToolbar.textStyle = textItem.textStyle
        textViewAccessoryToolbar.textStyle = textItem.textStyle

        textToolbar.decorationStyle = textItem.decorationStyle
        textViewAccessoryToolbar.decorationStyle = textItem.decorationStyle

        textView.text = textItem.text
        updateTextViewAttributes(using: textItem)

        imageEditorView.canvasView.hiddenItemId = textItem.itemId

        UIView.animate(withDuration: 0.2) {
            self.textViewContainer.alpha = 1
        }
        textView.becomeFirstResponder()
    }

    func finishTextEditing(applyEdits: Bool) {
        guard textUIInitialized else { return }
        guard textView.isFirstResponder else { return }

        textView.acceptAutocorrectSuggestion()
        textView.resignFirstResponder()

        defer {
            currentTextItem = nil
        }

        guard applyEdits else { return }

        guard let currentTextItem = currentTextItem else { return }

        var textItem = currentTextItem.textItem

        // Update text's width.
        let view = imageEditorView.gestureReferenceView
        let viewBounds = view.bounds
        let imageFrame = ImageEditorCanvasView.imageFrame(forViewSize: viewBounds.size,
                                                          imageSize: model.srcImageSizePixels,
                                                          transform: model.currentTransform())
        let unitWidth = textView.width / imageFrame.width
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
        textItem = textItem.copy(textStyle: textToolbar.textStyle, decorationStyle: textToolbar.decorationStyle)

        // Deleting all text results in text object being deleted.
        guard let text = textView.text?.ows_stripped(), !text.isEmpty else {
            if model.has(itemForId: textItem.itemId) {
                model.remove(item: textItem)
            }
            return
        }

        // Update text.
        textItem = textItem.copy(withText: text, color: textToolbar.colorPickerView.selectedValue)

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

        imageEditorView.selectedTextItemId = textItem.itemId
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
        finishTextEditing(applyEdits: true)
    }

    @objc
    func didTapTextStyleButton(sender: UIButton) {
        let currentTextStyle = textToolbar.textStyle
        let nextTextStyle = MediaTextView.TextStyle(rawValue: currentTextStyle.rawValue + 1) ?? .regular

        // Update selected text object if any.
        if let selectedTextItemId = imageEditorView.selectedTextItemId,
           let selectedTextItem = model.item(forId: selectedTextItemId) as? ImageEditorTextItem {
            let newTextItem = selectedTextItem.copy(textStyle: nextTextStyle, decorationStyle: textToolbar.decorationStyle)
            model.replace(item: newTextItem)
        }

        // Update toolbar.
        textToolbar.textStyle = nextTextStyle
        textViewAccessoryToolbar.textStyle = nextTextStyle

        // Update text view.
        if textView.isFirstResponder {
            updateTextViewAttributes(using: textToolbar)
        }
    }

    @objc
    func didTapDecorationStyleButton(sender: UIButton) {
        let currentDecorationStyle = textToolbar.decorationStyle
        var nextDecorationStyle = MediaTextView.DecorationStyle(rawValue: currentDecorationStyle.rawValue + 1) ?? .none
        if nextDecorationStyle == .outline {
            nextDecorationStyle = .none
        }

        // Update selected text object if any.
        if let selectedTextItemId = imageEditorView.selectedTextItemId,
           let selectedTextItem = model.item(forId: selectedTextItemId) as? ImageEditorTextItem {
            let newTextItem = selectedTextItem.copy(textStyle: textToolbar.textStyle, decorationStyle: nextDecorationStyle)
            model.replace(item: newTextItem)
        }

        // Update toolbar.
        textToolbar.decorationStyle = nextDecorationStyle
        textViewAccessoryToolbar.decorationStyle = nextDecorationStyle

        // Update text view.
        if textView.isFirstResponder {
            updateTextViewAttributes(using: textToolbar)
        }
    }
}

// MARK: - UITextViewDelegate

extension ImageEditorViewController: UITextViewDelegate {

    func textViewDidBeginEditing(_ textView: UITextView) {
        updateTextUIVisibility()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        UIView.animate(withDuration: 0.2) {
            self.imageEditorView.canvasView.hiddenItemId = nil
            self.textViewContainer.alpha = 0
        }
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
        owsAssertDebug(imageEditorView.selectedTextItemId == textItem.itemId)
        currentTextItem = (textItem, false)
        beginTextEditing()
    }

    func imageEditorView(_ imageEditorView: ImageEditorView, didMoveTextItem textItem: ImageEditorTextItem) {

    }

    func imageEditorViewDidUpdateSelection(_ imageEditorView: ImageEditorView) {
        if let selectedTextItemId = imageEditorView.selectedTextItemId,
           let textItem = model.item(forId: selectedTextItemId) as? ImageEditorTextItem {
            mode = .text

            textToolbar.colorPickerView.selectedValue = textItem.color
            textViewAccessoryToolbar.colorPickerView.selectedValue = textItem.color

            textToolbar.textStyle = textItem.textStyle
            textViewAccessoryToolbar.textStyle = textItem.textStyle

            textToolbar.decorationStyle = textItem.decorationStyle
            textViewAccessoryToolbar.decorationStyle = textItem.decorationStyle
        } else {
            mode = .draw
        }

        updateTextUIVisibility()
    }

    func imageEditorDidRequestToolbarVisibilityUpdate(_ imageEditorView: ImageEditorView) {
        updateControlsVisibility()
    }
}
