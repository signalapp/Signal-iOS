//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

@objc
public class CVBodyTextLabel: NSObject {

    public struct DataItem: Equatable {
        public enum DataType: UInt, Equatable, CustomStringConvertible {
            case link
            case address
            case phoneNumber
            case date
            case transitInformation
            case emailAddress

            // MARK: - CustomStringConvertible

            public var description: String {
                switch self {
                case .link:
                    return ".link"
                case .address:
                    return ".address"
                case .phoneNumber:
                    return ".phoneNumber"
                case .date:
                    return ".date"
                case .transitInformation:
                    return ".transitInformation"
                case .emailAddress:
                    return ".emailAddress"
                }
            }
        }

        public let dataType: DataType
        public let range: NSRange
        public let snippet: String
        public let url: URL

        public init(dataType: DataType, range: NSRange, snippet: String, url: URL) {
            self.dataType = dataType
            self.range = range
            self.snippet = snippet
            self.url = url
        }
    }

    // MARK: -

    public struct MentionItem: Equatable {
        public let mention: Mention
        public let range: NSRange

        public init(mention: Mention, range: NSRange) {
            self.mention = mention
            self.range = range
        }
    }

    // MARK: -

    public enum Item: Equatable {
        case dataItem(dataItem: DataItem)
        case mention(mentionItem: MentionItem)

        public var range: NSRange {
            switch self {
            case .dataItem(let dataItem):
                return dataItem.range
            case .mention(let mentionItem):
                return mentionItem.range
            }
        }
    }

    // MARK: -

    // TODO: This class is temporary until CVC's conformance to CVComponentDelegate
    //       is pure Swift.
    @objc(CVBodyTextLabelItemObject)
    public class ItemObject: NSObject {
        public let item: Item

        public init(item: Item) {
            self.item = item

            super.init()
        }
    }
    // MARK: -

    public struct Config {
        public let attributedString: NSAttributedString
        public let font: UIFont
        public let textColor: UIColor
        public let selectionColor: UIColor
        public let textAlignment: NSTextAlignment
        public let lineBreakMode: NSLineBreakMode
        public let numberOfLines: Int
        public let cacheKey: String
        public let items: [Item]

        public init(attributedString: NSAttributedString,
                    font: UIFont,
                    textColor: UIColor,
                    selectionColor: UIColor,
                    textAlignment: NSTextAlignment,
                    lineBreakMode: NSLineBreakMode,
                    numberOfLines: Int = 0,
                    cacheKey: String,
                    items: [Item]) {
            self.attributedString = attributedString
            self.font = font
            self.textColor = textColor
            self.selectionColor = selectionColor
            self.textAlignment = textAlignment
            self.lineBreakMode = lineBreakMode
            self.numberOfLines = numberOfLines
            self.cacheKey = cacheKey
            self.items = items
        }
    }

    // MARK: -

    private let label = Label()

    public var view: UIView { label }

    public override init() {
        label.backgroundColor = .clear
        label.isOpaque = false

        super.init()
    }

    public func configureForRendering(config: Config) {
        AssertIsOnMainThread()
        owsAssertDebug(label.config == nil)

        label.config = config
    }

    public func reset() {
        label.config = nil
        label.reset()
    }

    public static func measureSize(config: Config, maxWidth: CGFloat) -> CGSize {
        guard config.attributedString.length > 0 else {
            return .zero
        }
        let attributedString = Label.formatAttributedString(config: config)

        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(width: maxWidth, height: .greatestFiniteMagnitude))

        layoutManager.addTextContainer(textContainer)
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = config.lineBreakMode
        textContainer.maximumNumberOfLines = config.numberOfLines

        // The string must be assigned to the NSTextStorage *after* it has
        // an associated layout manager. Otherwise, the `NSOriginalFont`
        // attribute will not be defined correctly resulting in incorrect
        // measurement of character sets that font doesn't support natively
        // (CJK, Arabic, Emoji, etc.)
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        textStorage.setAttributedString(attributedString)

        // The NSTextStorage object owns all the other layout components,
        // so there are only weak references to it. In optimized builds,
        // this can result in it being freed before we perform measurement.
        // We can work around this by explicitly extending the lifetime of
        // textStorage until measurement is completed.
        return withExtendedLifetime(textStorage) { layoutManager.usedRect(for: textContainer).size }.ceil
    }

    // MARK: - Animation

    public func animate(selectedItem: Item) {
        label.animate(selectedItem: selectedItem)
    }

    // MARK: - Gestures

    public func itemForGesture(sender: UIGestureRecognizer) -> Item? {
        label.itemForGesture(sender: sender)
    }

    // MARK: -

    fileprivate class Label: UIView {

        fileprivate var config: Config? {
            didSet {
                reset()
                apply(config: config)
            }
        }

        private var activeItems = [Item]()
        private var activeMentions = [Mention]()

        private lazy var textStorage = NSTextStorage()
        private lazy var layoutManager = NSLayoutManager()
        private lazy var textContainer = NSTextContainer()

        private var animationTimer: Timer?

        // MARK: -

        override public init(frame: CGRect) {
            AssertIsOnMainThread()

            super.init(frame: frame)

            textStorage.addLayoutManager(layoutManager)
            layoutManager.addTextContainer(textContainer)

            isUserInteractionEnabled = true
            addInteraction(UIDragInteraction(delegate: self))
        }

        @available(*, unavailable, message: "Unimplemented")
        required public init?(coder aDecoder: NSCoder) {
            super.init(coder: aDecoder)
        }

        fileprivate func reset() {
            AssertIsOnMainThread()

            activeItems = []

            animationTimer?.invalidate()
            animationTimer = nil
        }

        private func apply(config: Config?) {
            AssertIsOnMainThread()

            guard let config = config else {
                reset()
                return
            }
            updateTextStorage(config: config)
        }

        open override func draw(_ rect: CGRect) {
            super.draw(rect)

            textContainer.size = bounds.size
            let glyphRange = layoutManager.glyphRange(for: textContainer)
            layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
        }

        // MARK: -

        fileprivate func updateTextStorage(config: Config) {
            AssertIsOnMainThread()

            textContainer.lineFragmentPadding = 0
            textContainer.lineBreakMode = config.lineBreakMode
            textContainer.maximumNumberOfLines = config.numberOfLines
            textContainer.size = bounds.size

            guard config.attributedString.length > 0 else {
                reset()
                textStorage.setAttributedString(NSAttributedString())
                setNeedsDisplay()
                return
            }

            let attributedString = Self.formatAttributedString(config: config)
            textStorage.setAttributedString(attributedString)
            setNeedsDisplay()
        }

        fileprivate static func formatAttributedString(config: Config) -> NSMutableAttributedString {
            let attributedString = NSMutableAttributedString(attributedString: config.attributedString)

            // The original attributed string may not have an overall font
            // assigned. Without it, measurement will not be correct. We
            // assign a font here with "add" which will not override any
            // ranges that already have a different font assigned.
            attributedString.addAttributeToEntireString(.font, value: config.font)

            var range = NSRange(location: 0, length: 0)
            var attributes = attributedString.attributes(at: 0, effectiveRange: &range)

            let paragraphStyle = attributes[.paragraphStyle] as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = config.lineBreakMode
            paragraphStyle.alignment = config.textAlignment
            attributes[.paragraphStyle] = paragraphStyle
            attributedString.setAttributes(attributes, range: range)
            return attributedString
        }

        fileprivate func updateAttributesForSelection(selectedItem: Item? = nil) {
            AssertIsOnMainThread()

            guard let config = config else {
                reset()
                return
            }
            guard let selectedItem = selectedItem else {
                apply(config: config)
                return
            }

            var attributes = textStorage.attributes(at: 0, effectiveRange: nil)
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.underlineColor] = config.selectionColor
            attributes[.foregroundColor] = config.selectionColor
            textStorage.addAttributes(attributes, range: selectedItem.range)

            setNeedsDisplay()
        }

        fileprivate func item(at location: CGPoint) -> Item? {
            AssertIsOnMainThread()

            guard let config = self.config else {
                return nil
            }
            guard textStorage.length > 0 else {
                return nil
            }

            let glyphRange = layoutManager.glyphRange(for: textContainer)
            let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            guard boundingRect.contains(location) else {
                return nil
            }

            let glyphIndex = layoutManager.glyphIndex(for: location, in: textContainer)
            let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

            for item in config.items {
                if item.range.contains(characterIndex) {
                    return item
                }
            }

            return nil
        }

        // MARK: - Animation

        public func animate(selectedItem: Item) {
            AssertIsOnMainThread()

            updateAttributesForSelection(selectedItem: selectedItem)
            self.animationTimer?.invalidate()
            self.animationTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                self?.updateAttributesForSelection()
            }
        }

        // MARK: - Gestures

        public func itemForGesture(sender: UIGestureRecognizer) -> Item? {
            AssertIsOnMainThread()

            let location = sender.location(in: self)
            guard let selectedItem = item(at: location) else {
                return nil
            }

            animate(selectedItem: selectedItem)

            return selectedItem
        }

        // MARK: -

        public override func updateConstraints() {
            super.updateConstraints()

            deactivateAllConstraints()
        }
    }
}

// MARK: -

extension CVBodyTextLabel.Label: UIDragInteractionDelegate {
    public func dragInteraction(_ interaction: UIDragInteraction,
                                itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        guard nil != self.config else {
            owsFailDebug("Missing config.")
            return []
        }
        let location = session.location(in: self)
        guard let selectedItem = self.item(at: location) else {
            return []
        }

        switch selectedItem {
        case .mention:
            // We don't let users drag mentions yet.
            return []
        case .dataItem(let dataItem):
            animate(selectedItem: selectedItem)

            let itemProvider = NSItemProvider(object: dataItem.snippet as NSString)
            let dragItem = UIDragItem(itemProvider: itemProvider)

            let glyphRange = self.layoutManager.glyphRange(forCharacterRange: selectedItem.range,
                                                           actualCharacterRange: nil)
            var textLineRects = [NSValue]()
            self.layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange,
                                                       withinSelectedGlyphRange: NSRange(location: NSNotFound,
                                                                                         length: 0),
                                                       in: self.textContainer) { (rect, _) in
                textLineRects.append(NSValue(cgRect: rect))
            }
            let previewParameters = UIDragPreviewParameters(textLineRects: textLineRects)
            let preview = UIDragPreview(view: self, parameters: previewParameters)
            dragItem.previewProvider = { preview }

            return [dragItem]
        }
    }
}
