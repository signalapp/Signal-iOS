//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol TextViewWithPlaceholderDelegate: AnyObject {
    /// A method invoked by the text field when its cursor/selection changed without any change
    /// to the text
    func textViewDidUpdateSelection(_ textView: TextViewWithPlaceholder)

    /// A method invoked by the text field whenever its text contents have changed
    /// This also implies an update to the selection
    func textViewDidUpdateText(_ textView: TextViewWithPlaceholder)

    /// A method invoked by the text field whenever the user tries to insert new text
    func textView(_ textView: TextViewWithPlaceholder, uiTextView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool
}

// MARK: -

public class TextViewWithPlaceholder: UIView {
    // MARK: - Public Properties

    /// A delegate to receive callbacks on any data updates
    public weak var delegate: TextViewWithPlaceholderDelegate?

    /// Fallback placeholder text if the field is empty
    public var placeholderText: String = "" {
        didSet {
            placeholderTextView.text = placeholderText
            textView.accessibilityLabel = placeholderText
        }
    }

    public func acceptAutocorrectSuggestion() {
        textView.acceptAutocorrectSuggestion()
    }

    /// Any text the user has input
    public var text: String? {
        get { textView.text }
        set {
            textView.text = newValue
            textViewDidChange(textView)
        }
    }

    public var returnKeyType: UIReturnKeyType {
        get { textView.returnKeyType }
        set { textView.returnKeyType = newValue }
    }

    public var dataDetectorTypes: UIDataDetectorTypes {
        get { textView.dataDetectorTypes }
        set { textView.dataDetectorTypes = newValue }
    }

    public var isEditable: Bool {
        get { textView.isEditable }
        set { textView.isEditable = newValue }
    }

    public var linkTextAttributes: [NSAttributedString.Key: Any] {
        get { textView.linkTextAttributes }
        set { textView.linkTextAttributes = newValue }
    }

    @discardableResult
    public override func becomeFirstResponder() -> Bool {
        textView.becomeFirstResponder()
    }

    @discardableResult
    public override func resignFirstResponder() -> Bool {
        textView.resignFirstResponder()
    }

    public override var canBecomeFirstResponder: Bool {
        textView.canBecomeFirstResponder
    }

    public override var isFirstResponder: Bool {
        textView.isFirstResponder
    }

    // MARK: - Private Properties

    private func buildTextView() -> UITextView {
        let textView = UITextView()
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear

        textView.font = UIFont.dynamicTypeBody
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainer.lineFragmentPadding = 0

        // This would make things align a bit more nicely, but it totally breaks VoiceOver for some reason
        // Leaving the default inset for now until I can track down what's tripping up VoiceOver.
        // textView.textContainerInset = .zero
        return textView
    }
    private lazy var textView = buildTextView()
    private lazy var placeholderTextView = buildTextView()

    // MARK: - Lifecycle

    public override init(frame: CGRect) {
        super.init(frame: frame)
        applyTheme()

        textView.delegate = self
        textView.isEditable = true
        placeholderTextView.isEditable = false
        placeholderTextView.isUserInteractionEnabled = false

        // The placeholderTextView is perfectly aligned with the textView to allow for us to easily
        // hide/show placeholder text without needing to manipulate the text property of our primary
        // text view. This makes VoiceOver navigation by dragging a bit tricky, since a user won't be
        // able to find the placeholder text. Let's disable it in VoiceOver. Instead, placeholderText
        // will be an accessibility label on the primary text view.
        placeholderTextView.accessibilityElementsHidden = true

        // Layout + Constraints
        for subview in [textView, placeholderTextView] {
            addSubview(subview)
            subview.autoPinEdgesToSuperviewEdges()
            subview.setCompressionResistanceHigh()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .ThemeDidChange, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Private

    @objc
    private func applyTheme() {
        placeholderTextView.textColor = Theme.placeholderColor
        textView.textColor = Theme.primaryTextColor
    }

    // MARK: - <UITextViewDelegate>

    // These help to track the user's edit focus
    private var oldStartCaretRect: CGRect = .null
    private var oldEndCaretRect: CGRect = .null
    private var focusedLineRect: CGRect = .null

    /// Returns a rect the height of a cursor and the width of the view, indicating the line the user is currently focused on
    /// This is determined by looking at the current position of the cursor(s) and how they have changed since this method
    /// was last invoked.
    /// If one cursor changed -> It's line has focus
    /// If both cursors changed -> The bottom cursor is designated to have tiebreaker focus
    /// Returns CGRectNull if there's no current selection
    func getUpdatedFocusLine() -> CGRect {
        guard let selectedRange = textView.selectedTextRange else {
            // Reset all stored rects to force an update whenever this is non-nil
            oldStartCaretRect = .null
            oldEndCaretRect = .null
            focusedLineRect = .null
            return .null
        }

        // Note: textView.caretRect(for:) will return CGRectNull while mid-edit
        // If the rects are null, we just ignore them.
        let startCaretRect = textView.caretRect(for: selectedRange.start)
        let endCaretRect = textView.caretRect(for: selectedRange.end)
        let didModifyStart = !startCaretRect.equalTo(oldStartCaretRect) && !startCaretRect.isNull
        let didModifyEnd = !endCaretRect.equalTo(oldEndCaretRect) && !startCaretRect.isNull

        // End cursor is the tiebreaker if they're both modified. Last writer wins
        if didModifyStart {
            oldStartCaretRect = startCaretRect
            focusedLineRect = createWideRect(from: startCaretRect)
        }
        if didModifyEnd {
            oldEndCaretRect = endCaretRect
            focusedLineRect = createWideRect(from: endCaretRect)
        }
        return focusedLineRect
    }

    /// Ensures the currently focused area is scrolled into the visible content inset
    /// If it's already visible, this will do nothing
    public func scrollToFocus(in scrollView: UIScrollView, animated: Bool) {
        let visibleRect = scrollView.bounds.inset(by: scrollView.adjustedContentInset)
        let rawCursorFocusRect = getUpdatedFocusLine()
        let cursorFocusRect = scrollView.convert(rawCursorFocusRect, from: self)
        let paddedCursorRect = cursorFocusRect.insetBy(dx: 0, dy: -6)

        let entireContentFits = scrollView.contentSize.height <= visibleRect.height
        let focusRect = entireContentFits ? visibleRect : paddedCursorRect

        // If we have a null rect, there's nowhere to scroll to
        // If the focusRect is already visible, there's no need to scroll
        guard !focusRect.isNull else { return }
        guard !visibleRect.contains(focusRect) else { return }

        let targetYOffset: CGFloat
        if focusRect.minY < visibleRect.minY {
            targetYOffset = focusRect.minY - scrollView.adjustedContentInset.top
        } else {
            let bottomEdgeOffset = scrollView.height - scrollView.adjustedContentInset.bottom
            targetYOffset = focusRect.maxY - bottomEdgeOffset
        }
        scrollView.setContentOffset(CGPoint(x: 0, y: targetYOffset), animated: animated)
    }

    /// Helper to take a rect and horizontally size it to the current bounds
    private func createWideRect(from rect: CGRect) -> CGRect {
        return CGRect(x: 0, y: rect.minY, width: width, height: rect.height)
    }
}

// MARK: -

extension TextViewWithPlaceholder: UITextViewDelegate {

    public func textViewDidChangeSelection(_ textView: UITextView) {
        delegate?.textViewDidUpdateSelection(self)
    }

    public func textViewDidChange(_ textView: UITextView) {
        let showPlaceholder = textView.text.isEmpty
        placeholderTextView.isHidden = !showPlaceholder

        delegate?.textViewDidUpdateText(self)
    }

    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        delegate?.textView(self, uiTextView: textView, shouldChangeTextIn: range, replacementText: text) ?? true
    }
}
