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
        textView.autoCenterInSuperview()
        textView.autoPinWidthToSuperviewMargins(relation: .lessThanOrEqual)
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
        updateTextView(color: textItem.color.color, font: textItem.font, decorationStyle: textItem.decorationStyle)
    }

    // Update UITextView to use style (font, color, decoration) as selected in provided TextToolbar.
    // This method needs to be called whenever user changes text styling while UITextView is active
    // in order to reflect the changes right away.
    func updateTextViewAttributes(using textToolbar: TextToolbar) {
        let fontPointSize = textView.font?.pointSize ?? ImageEditorTextItem.defaultFontSize
        updateTextView(color: textToolbar.paletteView.selectedValue.color,
                       font: ImageEditorTextItem.font(forTextStyle: textToolbar.textStyle, pointSize: fontPointSize),
                       decorationStyle: textToolbar.decorationStyle)
    }

    private func updateTextView(color: UIColor, font: UIFont, decorationStyle: ImageEditorTextItem.DecorationStyle) {
        var attributes: [NSAttributedString.Key: Any] = [ .font: font]

        let textColor: UIColor = {
            switch decorationStyle {
            case .none: return color
            default: return .white
            }
        }()
        attributes[.foregroundColor] = textColor

        if let paragraphStyle = NSParagraphStyle.default.mutableCopy() as? NSMutableParagraphStyle {
            paragraphStyle.alignment = .center
            attributes[.paragraphStyle] = paragraphStyle
        }

        switch decorationStyle {
        case .underline:
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.underlineColor] = color

        case .outline:
            attributes[.strokeWidth] = -3
            attributes[.strokeColor] = color

        case .inverted:
            attributes[.backgroundColor] = color

        default:
            break
        }

        textView.attributedText = NSAttributedString(string: textView.text, attributes: attributes)

        // This makes UITextView apply text styling to the text that user enters.
        textView.typingAttributes = attributes

        textView.invalidateIntrinsicContentSize()
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

        textToolbar.paletteView.selectedValue = textItem.color
        textViewAccessoryToolbar.paletteView.selectedValue = textItem.color

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
        textItem = textItem.copy(withText: text, color: textToolbar.paletteView.selectedValue)

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
        let nextTextStyle = ImageEditorTextItem.TextStyle(rawValue: currentTextStyle.rawValue + 1) ?? .regular

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
        var nextDecorationStyle = ImageEditorTextItem.DecorationStyle(rawValue: currentDecorationStyle.rawValue + 1) ?? .none
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

    // MARK: -

    class TextToolbar: UIView {

        let paletteView: ImageEditorPaletteView

        let textStyleButton = RoundMediaButton(image: #imageLiteral(resourceName: "media-editor-text-font"), backgroundStyle: .blur)
        var textStyle: ImageEditorTextItem.TextStyle = .regular

        let decorationStyleButton = RoundMediaButton(image: #imageLiteral(resourceName: "media-editor-text-style-1"), backgroundStyle: .blur)
        var decorationStyle: ImageEditorTextItem.DecorationStyle = .none {
            didSet {
                decorationStyleButton.isSelected = (decorationStyle != .none)
            }
        }

        init(currentColor: ImageEditorColor) {
            self.paletteView = ImageEditorPaletteView(currentColor: currentColor)
            super.init(frame: .zero)

            decorationStyleButton.setContentCompressionResistancePriority(.required, for: .vertical)
            decorationStyleButton.setImage(#imageLiteral(resourceName: "media-editor-text-style-2"), for: .selected)

            // A container with width capped at a predefined size,
            // centered in superview and constrained to layout margins.
            let stackViewLayoutGuide = UILayoutGuide()
            addLayoutGuide(stackViewLayoutGuide)
            addConstraints([
                stackViewLayoutGuide.centerXAnchor.constraint(equalTo: centerXAnchor),
                stackViewLayoutGuide.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
                stackViewLayoutGuide.topAnchor.constraint(equalTo: topAnchor),
                stackViewLayoutGuide.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2) ])
            addConstraint({
                let constraint = stackViewLayoutGuide.widthAnchor.constraint(equalToConstant: ImageEditorViewController.preferredToolbarContentWidth)
                constraint.priority = .defaultHigh
                return constraint
            }())

            // I had to use a custom layout guide because stack view isn't centered
            // but instead has slight offset towards the trailing edge.
            let stackView = UIStackView(arrangedSubviews: [ paletteView, textStyleButton, decorationStyleButton ])
            stackView.translatesAutoresizingMaskIntoConstraints = false
            stackView.alignment = .center
            stackView.spacing = 8
            stackView.setCustomSpacing(0, after: textStyleButton)
            addSubview(stackView)
            addConstraints([
                stackView.leadingAnchor.constraint(equalTo: stackViewLayoutGuide.leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: stackViewLayoutGuide.trailingAnchor,
                                                    constant: decorationStyleButton.layoutMargins.trailing),
                stackView.topAnchor.constraint(equalTo: stackViewLayoutGuide.topAnchor),
                stackView.bottomAnchor.constraint(equalTo: stackViewLayoutGuide.bottomAnchor) ])
        }

        @available(iOS, unavailable, message: "Use init(currentColor:)")
        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
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

            textToolbar.paletteView.selectedValue = textItem.color
            textViewAccessoryToolbar.paletteView.selectedValue = textItem.color

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

// TODO: Clean up this class.
class VAlignTextView: UITextView {

    private var kvoObservation: NSKeyValueObservation?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)

        keyboardAppearance = .dark

        kvoObservation = observe(\.contentSize, options: [.new]) { [weak self] _, _ in
            guard let self = self else { return }
            self.adjustFontSizeIfNecessary()
        }
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func adjustFontSizeIfNecessary() {
        // TODO: Figure out correct way to handle long text and implement it.
    }

    // MARK: - Key Commands

    override var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(self.modifiedReturnPressed(sender:)), discoverabilityTitle: "Add Text"),
            UIKeyCommand(input: "\r", modifierFlags: .alternate, action: #selector(self.modifiedReturnPressed(sender:)), discoverabilityTitle: "Add Text")
        ]
    }

    @objc
    private func modifiedReturnPressed(sender: UIKeyCommand) {
        Logger.verbose("")

        acceptAutocorrectSuggestion()
        resignFirstResponder()
    }
}
