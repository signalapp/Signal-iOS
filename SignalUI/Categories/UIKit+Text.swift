//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public extension UISearchBar {

    var textField: UITextField? {
        return searchTextField
    }
}

// MARK: -

public extension UITextField {

    func acceptAutocorrectSuggestion() {
        inputDelegate?.selectionWillChange(self)
        inputDelegate?.selectionDidChange(self)
    }
}

// MARK: -

public extension UITextView {

    func acceptAutocorrectSuggestion() {
        // https://stackoverflow.com/a/27865136/4509555
        inputDelegate?.selectionWillChange(self)
        inputDelegate?.selectionDidChange(self)
    }

    func characterIndex(of location: CGPoint) -> Int? {
        return textContainer.characterIndex(of: location, textStorage: textStorage, layoutManager: layoutManager)
    }
}

// MARK: -

public extension NSTextContainer {

    func characterIndex(
        of location: CGPoint,
        textStorage: NSTextStorage,
        layoutManager: NSLayoutManager
    ) -> Int? {
        guard textStorage.length > 0 else {
            return nil
        }

        let glyphRange = layoutManager.glyphRange(for: self)
        let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: self)
        guard boundingRect.contains(location) else {
            return nil
        }

        let glyphIndex = layoutManager.glyphIndex(for: location, in: self)

        // We have the _closest_ index, but that doesn't mean we tapped in a glyph.
        // Check that directly.
        // This will catch the below case, where "*" is the tap location:
        //
        // This is the first line that is long.
        // Tap on the second line.    *
        //
        // The bounding rect includes the empty space below the first line,
        // but the tap doesn't actually lie on any glyph.
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: self)
        guard glyphRect.contains(location) else {
            return nil
        }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        return characterIndex
    }

    func boundingRects(
        ofCharacterRanges ranges: [NSRange],
        textStorage: NSTextStorage,
        layoutManager: NSLayoutManager
    ) -> [CGRect] {
        return boundingRects(
            ofCharacterRanges: ranges,
            rangeMap: { return $0 },
            textStorage: textStorage,
            layoutManager: layoutManager,
            transform: { rect, _ in return rect }
        )
    }

    func boundingRects<T, R>(
        ofCharacterRanges ranges: [T],
        rangeMap: (T) -> NSRange,
        textStorage: NSTextStorage,
        layoutManager: NSLayoutManager,
        textContainerInsets: UIEdgeInsets = .zero,
        transform: @escaping (CGRect, T) -> R
    ) -> [R] {
        return ranges.flatMap { (value: T) -> [R] in
            let range = rangeMap(value)
            guard textStorage.length >= range.upperBound else {
                return []
            }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var perLineResults = [R]()
            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: self
            ) { rect, stop in
                if rect.maxY > self.size.height {
                    stop.pointee = true
                    return
                }
                perLineResults.append(transform(
                    rect.offsetBy(dx: textContainerInsets.left, dy: textContainerInsets.top),
                    value
                ))
            }
            return perLineResults
        }
    }
}

// MARK: -

extension UILabel {

    public func characterIndex(of location: CGPoint) -> Int? {
        guard let (textContainer, textStorage, layoutManager) = makeMatchingTextContainer() else {
            return nil
        }
        return textContainer.characterIndex(of: location, textStorage: textStorage, layoutManager: layoutManager)
    }

    func boundingRects(ofCharacterRanges ranges: [NSRange]) -> [CGRect] {
        guard let (textContainer, textStorage, layoutManager) = makeMatchingTextContainer() else {
            return []
        }
        return textContainer.boundingRects(ofCharacterRanges: ranges, textStorage: textStorage, layoutManager: layoutManager)
    }

    func boundingRects<T, R>(
        ofCharacterRanges ranges: [T],
        rangeMap: (T) -> NSRange,
        transform: @escaping (CGRect, T) -> R
    ) -> [R] {
        guard let (textContainer, textStorage, layoutManager) = makeMatchingTextContainer() else {
            return []
        }
        return textContainer.boundingRects(
            ofCharacterRanges: ranges,
            rangeMap: rangeMap,
            textStorage: textStorage,
            layoutManager: layoutManager,
            transform: transform
        )
    }

    // This is somewhat inconsistent; labels with text alignments and who knows what
    // other attributes applied may not do a great job at identifying the index.
    // Eventually this should be removed in favor of using UITextView everywhere.
    private func makeMatchingTextContainer() -> (NSTextContainer, NSTextStorage, NSLayoutManager)? {
        let attrString: NSAttributedString
        if let attributedText {
            attrString = attributedText
        } else if let text {
            attrString = NSAttributedString(string: text, attributes: [.font: self.font as Any])
        } else {
            return nil
        }
        let textStorage = NSTextStorage(attributedString: attrString)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: self.bounds.size)
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = self.numberOfLines
        textContainer.lineBreakMode = self.lineBreakMode
        layoutManager.addTextContainer(textContainer)

        return (textContainer, textStorage, layoutManager)
    }
}

// MARK: -

public extension NSTextAlignment {

    static var trailing: NSTextAlignment {
        CurrentAppContext().isRTL ? .left : .right
    }
}

// MARK: -

extension NSTextAlignment: CustomStringConvertible {

    public var description: String {
        switch self {
        case .left:
            return "left"
        case .center:
            return "center"
        case .right:
            return "right"
        case .justified:
            return "justified"
        case .natural:
            return "natural"
        @unknown default:
            return "unknown"
        }
    }
}
