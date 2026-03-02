//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/**
 * Given an attributed string and a highlightRange, draws a colored capsule behind the characters in highlightRange.
 * The color of the capsule is determined by the textColor with opacity decreased.
 * highlightFont allows for the capsule text to be a different font (e.g. bold or not bold) from the rest of the attributed text.
 * Since we don't want the highlight range to wrap, but we may want the rest of the range to wrap, this class manually
 * truncates text longer than the given width and adds an ellipsis.
 */
public class CVCapsuleLabel: UILabel {
    public enum PresentationContext {
        case nonMessageBubble
        case messageBubbleRegular
        case messageBubbleQuoteReplyIncoming
        case messageBubbleQuoteReplyOutgoing
    }

    public let highlightRange: NSRange
    public let highlightFont: UIFont
    public let axLabelPrefix: String?
    public let presentationContext: PresentationContext
    public let onTap: (() -> Void)?

    // *CapsuleInset is how far beyond the text the capsule expands.
    // *Offset is how shifted BOTH capsule & text are from the edge of the view.
    private static let horizontalCapsuleInset: CGFloat = 8
    private static let verticalCapsuleInset: CGFloat = 1
    private static let verticalOffset: CGFloat = 3
    private static let horizontalOffset: CGFloat = 8

    public init(
        attributedText: NSAttributedString,
        textColor: UIColor,
        font: UIFont?,
        highlightRange: NSRange,
        highlightFont: UIFont,
        axLabelPrefix: String?,
        presentationContext: PresentationContext,
        lineBreakMode: NSLineBreakMode = .byTruncatingTail,
        numberOfLines: Int = 0,
        onTap: (() -> Void)?,
    ) {
        self.highlightRange = highlightRange
        self.highlightFont = highlightFont
        self.axLabelPrefix = axLabelPrefix
        self.presentationContext = presentationContext
        self.onTap = onTap

        super.init(frame: .zero)

        self.font = font
        self.textColor = textColor
        self.lineBreakMode = lineBreakMode
        self.numberOfLines = numberOfLines

        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapMemberLabel)))

        let attributedString = NSMutableAttributedString(attributedString: attributedText)
        attributedString.addAttribute(.font, value: self.font!, range: attributedText.entireRange)
        attributedString.addAttribute(.foregroundColor, value: textColor, range: attributedText.entireRange)

        // The highlighted text may have different font than the sender name
        attributedString.addAttribute(.font, value: highlightFont, range: highlightRange)
        self.attributedText = attributedString
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var capsuleColor: UIColor {
        switch presentationContext {
        case .messageBubbleQuoteReplyOutgoing:
            return UIColor.white.withAlphaComponent(0.36)
        case .messageBubbleQuoteReplyIncoming:
            if Theme.isDarkThemeEnabled {
                return UIColor.white.withAlphaComponent(0.16)
            }
            return UIColor.black.withAlphaComponent(0.1)
        case .messageBubbleRegular, .nonMessageBubble:
            if Theme.isDarkThemeEnabled {
                return textColor.withAlphaComponent(0.32)
            }
            return textColor.withAlphaComponent(0.14)
        }
    }

    @objc
    func didTapMemberLabel() {
        onTap?()
    }

    /// Takes an attributed string, its font, and color, and returns a new attributed string,
    /// truncated to fit within the max width, with an ellipsis appended to the end.
    private static func truncateStringUntilFits(
        string: NSAttributedString,
        maxWidth: CGFloat,
        font: UIFont,
        textColor: UIColor,
    ) -> NSAttributedString {
        guard string.size().width > maxWidth else {
            return string
        }

        let ellipsesUnicode = NSMutableAttributedString(string: "\u{2026}")
        ellipsesUnicode.addAttribute(.font, value: font, range: ellipsesUnicode.entireRange)
        ellipsesUnicode.addAttribute(
            .foregroundColor,
            value: textColor,
            range: ellipsesUnicode.entireRange,
        )
        let ellipsesWidth = ellipsesUnicode.size().width
        let newMaxWidth = maxWidth - ellipsesWidth

        let truncatedString: NSMutableAttributedString = NSMutableAttributedString(attributedString: string)

        // Since NSAttributedStrings count UTF-16 code points, we should
        // use rangeOfComposedCharacterSequences to delete the total range
        // for a single "visible" char to avoid breaking up emojis.
        while truncatedString.size().width > newMaxWidth {
            let totalCharRange = (truncatedString.string as NSString).rangeOfComposedCharacterSequences(
                for:
                NSRange(
                    location: truncatedString.length - 1,
                    length: 1,
                ),
            )
            truncatedString.deleteCharacters(in: totalCharRange)
        }

        truncatedString.append(ellipsesUnicode)
        return truncatedString
    }

    /// Takes an attributed string & its properties, and formats it correctly to prevent wrapping of the highlighted range.
    /// Any part of the attributed string outside of the highlight range can wrap as usual, but the highlighted range should
    /// stay on one line and truncate using truncateStringUntilFits().
    /// For example, "Jane (Engineer)" with () indicating the highlighted range, should either stay on one line width permitting, or become:
    ///
    /// "Jane
    /// (Engineer)"
    ///
    /// If the member label is too long for the given space on the next line it should become:
    ///
    /// "Jane
    /// (Eng...)"
    ///
    /// A long profile name might look like this:
    ///  "Jane Long Profile
    ///  Name (Engineer)"
    ///
    ///  or, if less wide,
    ///  "Jane
    ///  Long
    ///  Profile
    ///  Name
    ///  (Eng...)"
    ///
    ///  A truncated member label should always be on its own line.
    private static func formatCapsuleString(
        attributedString: NSAttributedString,
        highlightRange: NSRange,
        highlightFont: UIFont,
        textColor: UIColor,
        maxWidth: CGFloat,
    ) -> (NSAttributedString, NSRange)? {
        let totalStringWidth = attributedString.size().width
        let highlightedString = attributedString.attributedSubstring(from: highlightRange)
        let highlightedStringWidth = highlightedString.size().width

        let nonHighlightRange = NSRange(location: 0, length: highlightRange.location)
        let nonHighlightString = attributedString.attributedSubstring(from: nonHighlightRange)

        let breakString = NSAttributedString(string: "\n")

        // If highlight text width or total string width is greater than line width,
        // move highlight to the next line to avoid wrapping, and truncate it if needed.
        if highlightedStringWidth > maxWidth || totalStringWidth > maxWidth {
            let truncatedHighlightString = Self.truncateStringUntilFits(
                string: highlightedString,
                maxWidth: maxWidth,
                font: highlightFont,
                textColor: textColor,
            )

            if !nonHighlightString.isEmpty {
                let newTotalString = nonHighlightString + breakString + truncatedHighlightString
                let newHighlightRange = (newTotalString.string as NSString).range(of: truncatedHighlightString.string)
                return (newTotalString, newHighlightRange)
            }

            return (truncatedHighlightString, truncatedHighlightString.entireRange)
        }

        // Everything fits on one line! Return as-is.
        return (attributedString, highlightRange)
    }

    private func textContainerForFormattedString(
        layoutManager: NSLayoutManager,
        textStorage: NSTextStorage,
        size: CGSize,
    ) -> NSTextContainer {
        let textContainer = NSTextContainer(size: size)
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = self.numberOfLines
        textContainer.lineBreakMode = self.lineBreakMode
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        return textContainer
    }

    private func calculateHorizontalOffset() -> CGFloat {
        // We only need to offset the capsule & text horizontally if the edge of the view
        // might cut it off because its naturally aligned.
        let needsHorizontalOffset = textAlignment == .natural
        if needsHorizontalOffset {
            return CurrentAppContext().isRTL ? -Self.horizontalOffset : Self.horizontalOffset
        }
        return 0
    }

    override public func drawText(in rect: CGRect) {
        guard let attributedText, let textColor else {
            return super.drawText(in: rect)
        }

        owsAssertDebug(numberOfLines == 0 || numberOfLines == 1, "CVCapsule wrapping behavior undefined")

        let hOffset = calculateHorizontalOffset()
        let maxWidth = rect.width - (2 * Self.horizontalCapsuleInset + abs(hOffset))
        let formattedStringData = CVCapsuleLabel.formatCapsuleString(
            attributedString: attributedText,
            highlightRange: highlightRange,
            highlightFont: highlightFont,
            textColor: textColor,
            maxWidth: maxWidth,
        )

        guard let (formattedAttributedString, newHighlightRange) = formattedStringData else {
            return super.drawText(in: rect)
        }

        let layoutManager = NSLayoutManager()
        let textStorage = NSTextStorage(attributedString: formattedAttributedString)
        let textContainer = textContainerForFormattedString(
            layoutManager: layoutManager,
            textStorage: textStorage,
            size: rect.size,
        )
        let highlightGlyphRange = layoutManager.glyphRange(forCharacterRange: newHighlightRange, actualCharacterRange: nil)
        let highlightColor = capsuleColor
        layoutManager.enumerateEnclosingRects(forGlyphRange: highlightGlyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { rect, _ in
            let vCapsuleOffset = -Self.verticalCapsuleInset + Self.verticalOffset
            let roundedRect = rect.offsetBy(
                dx: hOffset,
                dy: vCapsuleOffset,
            ).insetBy(
                dx: -Self.horizontalCapsuleInset,
                dy: -Self.verticalCapsuleInset,
            )
            let path = UIBezierPath(roundedRect: roundedRect, cornerRadius: roundedRect.height / 2)
            highlightColor.setFill()
            path.fill()
            layoutManager.drawGlyphs(forGlyphRange: highlightGlyphRange, at: CGPoint(x: hOffset, y: Self.verticalOffset))
        }

        let newNonHighlightRange = NSRange(location: 0, length: newHighlightRange.location)
        let nonHighlightGlyphRange = layoutManager.glyphRange(forCharacterRange: newNonHighlightRange, actualCharacterRange: nil)
        layoutManager.drawGlyphs(forGlyphRange: nonHighlightGlyphRange, at: CGPoint(x: 0, y: Self.verticalOffset))
    }

    override public var intrinsicContentSize: CGSize {
        return labelSize(maxWidth: .greatestFiniteMagnitude)
    }

    public static func measureLabel(
        attributedText: NSAttributedString,
        font: UIFont,
        highlightRange: NSRange,
        highlightFont: UIFont,
        presentationContext: CVCapsuleLabel.PresentationContext,
        maxWidth: CGFloat,
    ) -> CGSize {
        let label = CVCapsuleLabel(
            attributedText: attributedText,
            textColor: .black,
            font: font,
            highlightRange: highlightRange,
            highlightFont: highlightFont,
            axLabelPrefix: nil,
            presentationContext: presentationContext,
            onTap: nil,
        )
        return label.labelSize(maxWidth: maxWidth)
    }

    public func labelSize(maxWidth: CGFloat) -> CGSize {
        guard let attributedText, !attributedText.isEmpty else { return .zero }
        let hOffset = calculateHorizontalOffset()

        let maxWidthMinusInsets = maxWidth - (abs(hOffset) + Self.horizontalCapsuleInset * 2)

        owsAssertDebug(numberOfLines == 0 || numberOfLines == 1, "CVCapsule wrapping behavior undefined")

        let formattedStringData = CVCapsuleLabel.formatCapsuleString(
            attributedString: attributedText,
            highlightRange: highlightRange,
            highlightFont: highlightFont,
            textColor: textColor,
            maxWidth: maxWidthMinusInsets,
        )

        guard let (formattedAttributedString, _) = formattedStringData else {
            return .zero
        }

        let layoutManager = NSLayoutManager()
        let size = CGSize(width: maxWidthMinusInsets, height: .greatestFiniteMagnitude)

        let textStorage = NSTextStorage(attributedString: formattedAttributedString)
        let textContainer = textContainerForFormattedString(
            layoutManager: layoutManager,
            textStorage: textStorage,
            size: size,
        )

        let measureSize = layoutManager.usedRect(for: textContainer).size.ceil
        let finalHeight = measureSize.height + Self.verticalOffset + Self.verticalCapsuleInset * 2
        let finalWidth = measureSize.width + Self.horizontalCapsuleInset * 2 + abs(hOffset)
        return CGSize(width: finalWidth, height: finalHeight)
    }

    override public var accessibilityLabel: String? {
        get {
            if let axLabelPrefix, let text = self.text {
                return axLabelPrefix + text
            }
            return super.accessibilityLabel
        }
        set { super.accessibilityLabel = newValue }
    }

    override public var accessibilityTraits: UIAccessibilityTraits {
        get {
            var axTraits = super.accessibilityTraits
            if onTap != nil {
                axTraits.insert(.button)
            }
            return axTraits
        }
        set {
            super.accessibilityTraits = newValue
        }
    }
}
