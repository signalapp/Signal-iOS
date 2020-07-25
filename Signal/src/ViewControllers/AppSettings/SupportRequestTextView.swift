//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol SupportRequestTextViewDelegate: class {
    /// A method invoked by the description field when its cursor/selection changed without any change
    /// to the text
    func textViewDidUpdateSelection(_ textView: SupportRequestTextView)

    /// A method invoked by the description field whenever its text contents have changed
    /// This also implies an update to the selection
    func textViewDidUpdateText(_ textView: SupportRequestTextView)
}

class SupportRequestTextView: UIView, UITextViewDelegate {
    // MARK: - Public Properties

    /// A delegate to receive callbacks on any data updates
    weak var delegate: SupportRequestTextViewDelegate?

    /// Fallback placeholder text if the field is empty
    var placeholderText: String = "" {
        didSet {
            configurePlaceholder()
        }
    }

    /// Any text the user has input
    var text: String {
        return showPlaceholder ? "" : textView.text
    }

    // MARK: - Private Properties
    private let textView: UITextView = {
        let textView = UITextView(forAutoLayout: ())
        textView.font = UIFont.ows_dynamicTypeBody
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.clipsToBounds = false
        textView.backgroundColor = .clear
        textView.adjustsFontForContentSizeCategory = true
        return textView
    }()

    private var showPlaceholder: Bool = true {
        didSet {
            configurePlaceholder()
        }
    }

    // MARK: - Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)

        // Layout + Constraints
        addSubview(textView)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.autoPinEdgesToSuperviewEdges()
        textView.setCompressionResistanceHigh()

        // Content
        textView.delegate = self
        configurePlaceholder()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTheme() {
        configurePlaceholder()
    }

    // MARK: - Private

    private func configurePlaceholder() {
        textView.textColor = showPlaceholder ? Theme.placeholderColor : Theme.primaryTextColor
        if showPlaceholder {
            textView.text = placeholderText
        }
    }

    // MARK: - <UITextViewDelegate>

    func textViewDidBeginEditing(_: UITextView) {
        if showPlaceholder {
            textView.text = ""
        }
        showPlaceholder = false
    }

    func textViewDidEndEditing(_: UITextView) {
        showPlaceholder = (textView.text.count == 0)
    }

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

    // MARK: - <UITextViewDelegate>

    func textViewDidChangeSelection(_ textView: UITextView) {
        delegate?.textViewDidUpdateSelection(self)
    }

    func textViewDidChange(_ textView: UITextView) {
        delegate?.textViewDidUpdateText(self)
    }

    /// Helper to take a rect and horizontally size it to the current bounds
    private func createWideRect(from rect: CGRect) -> CGRect {
        return CGRect(x: 0, y: rect.minY, width: width, height: rect.height)
    }
}
