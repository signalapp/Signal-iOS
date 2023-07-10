//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public class CVTextLabel: NSObject {

    // MARK: -

    public struct MentionItem: Equatable {
        public let mentionUUID: UUID
        public let range: NSRange

        public init(mentionUUID: UUID, range: NSRange) {
            self.mentionUUID = mentionUUID
            self.range = range
        }
    }

    // MARK: -

    public struct ReferencedUserItem: Equatable {
        public let address: SignalServiceAddress
        public let range: NSRange

        public init(address: SignalServiceAddress, range: NSRange) {
            self.address = address
            self.range = range
        }
    }

    // MARK: -

    public struct UnrevealedSpoilerItem: Equatable {
        public let spoilerId: Int
        public let interactionUniqueId: String
        public let interactionIdentifier: InteractionSnapshotIdentifier
        public let range: NSRange

        public init(
            spoilerId: Int,
            interactionUniqueId: String,
            interactionIdentifier: InteractionSnapshotIdentifier,
            range: NSRange
        ) {
            self.spoilerId = spoilerId
            self.interactionUniqueId = interactionUniqueId
            self.interactionIdentifier = interactionIdentifier
            self.range = range
        }
    }

    // MARK: -

    public enum Item: Equatable, CustomStringConvertible {
        case dataItem(dataItem: TextCheckingDataItem)
        case mention(mentionItem: MentionItem)
        case referencedUser(referencedUserItem: ReferencedUserItem)
        case unrevealedSpoiler(UnrevealedSpoilerItem)

        public var range: NSRange {
            switch self {
            case .dataItem(let dataItem):
                return dataItem.range
            case .mention(let mentionItem):
                return mentionItem.range
            case .referencedUser(let referencedUserItem):
                return referencedUserItem.range
            case .unrevealedSpoiler(let item):
                return item.range
            }
        }

        public var description: String {
            switch self {
            case .dataItem:
                return ".dataItem"
            case .mention:
                return ".mention"
            case .referencedUser:
                return ".referencedUser"
            case .unrevealedSpoiler:
                return ".unrevealedSpoiler"
            }
        }
    }

    public enum LinkifyStyle {
        case linkAttribute
        case underlined(bodyTextColor: UIColor)
    }

    // MARK: -

    public struct Config {
        public let text: CVTextValue
        public let displayConfig: HydratedMessageBody.DisplayConfiguration
        public let font: UIFont
        public let textColor: UIColor
        public let selectionStyling: [NSAttributedString.Key: Any]
        public let textAlignment: NSTextAlignment
        public let lineBreakMode: NSLineBreakMode
        public let numberOfLines: Int
        public let cacheKey: String
        public let items: [Item]
        public let linkifyStyle: CVTextLabel.LinkifyStyle

        public init(
            text: CVTextValue,
            displayConfig: HydratedMessageBody.DisplayConfiguration,
            font: UIFont,
            textColor: UIColor,
            selectionStyling: [NSAttributedString.Key: Any],
            textAlignment: NSTextAlignment,
            lineBreakMode: NSLineBreakMode,
            numberOfLines: Int = 0,
            cacheKey: String? = nil,
            items: [Item],
            linkifyStyle: CVTextLabel.LinkifyStyle
        ) {
            self.text = text
            self.displayConfig = displayConfig
            self.font = font
            self.textColor = textColor
            self.selectionStyling = selectionStyling
            self.textAlignment = textAlignment
            self.lineBreakMode = lineBreakMode
            self.numberOfLines = numberOfLines

            if let cacheKey = cacheKey {
                self.cacheKey = cacheKey
            } else {
                self.cacheKey = "\(text.cacheKey),\(displayConfig.sizingCacheKey),\(font.fontName),\(font.pointSize),\(numberOfLines),\(lineBreakMode.rawValue),\(textAlignment.rawValue)"
            }

            self.items = items
            self.linkifyStyle = linkifyStyle
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
        label.config = config
    }

    public func reset() {
        label.config = nil
        label.reset()
    }

    public class Measurement: CVMeasurementObject {
        public let size: CGSize
        public let lastLineRect: CGRect?

        init(size: CGSize, lastLineRect: CGRect?) {
            self.size = size
            self.lastLineRect = lastLineRect
        }

        static let empty = { Measurement(size: .zero, lastLineRect: nil) }()

        // MARK: - Equatable

        public static func == (lhs: Measurement, rhs: Measurement) -> Bool {
            lhs.size == rhs.size && lhs.lastLineRect == rhs.lastLineRect
        }
    }

    public static func measureSize(config: Config, maxWidth: CGFloat) -> Measurement {
        guard config.text.isEmpty.negated else {
            return .empty
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
        return withExtendedLifetime(textStorage) {
            let glyphRange = layoutManager.glyphRange(for: textContainer)
            var lastLineRect: CGRect?
            if glyphRange.location != NSNotFound,
               glyphRange.length > 0 {
                let lastGlyphIndex = glyphRange.length - 1
                lastLineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: lastGlyphIndex,
                                                                      effectiveRange: nil,
                                                                      withoutAdditionalLayout: true)
            }

            let size = layoutManager.usedRect(for: textContainer).size.ceil
            return Measurement(size: size, lastLineRect: lastLineRect)
        }
    }

    // MARK: - Gestures

    public func itemForGesture(sender: UIGestureRecognizer) -> Item? {
        label.itemForGesture(sender: sender)
    }

    public func animate(selectedItem: Item) {
        label.animate(selectedItem: selectedItem)
    }

    // MARK: - Linkification

    public static func linkifyData(
        attributedText: NSMutableAttributedString,
        linkifyStyle: LinkifyStyle,
        items: [CVTextLabel.Item]
    ) {

        // Sort so that we can detect overlap.
        let items = items.sorted {
            $0.range.location < $1.range.location
        }

        for item in items {
            let range = item.range

            switch item {
            case .mention, .referencedUser, .unrevealedSpoiler:
                // Do nothing; these are already styled.
                continue
            case .dataItem(let dataItem):
                guard let link = dataItem.url.absoluteString.nilIfEmpty else {
                    owsFailDebug("Could not build data link.")
                    continue
                }

                switch linkifyStyle {
                case .linkAttribute:
                    attributedText.addAttribute(.link, value: link, range: range)
                case .underlined(let bodyTextColor):
                    attributedText.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    attributedText.addAttribute(.underlineColor, value: bodyTextColor, range: range)
                }
            }
        }
    }

    // MARK: -

    fileprivate class Label: UIView {

        fileprivate var config: Config? {
            didSet {
                reset()
                apply(config: config)
            }
        }

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
            contentMode = .redraw
        }

        @available(*, unavailable, message: "Unimplemented")
        required public init?(coder aDecoder: NSCoder) {
            super.init(coder: aDecoder)
        }

        fileprivate func reset() {
            AssertIsOnMainThread()

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

            guard config.text.isEmpty.negated else {
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
            let attributedString: NSMutableAttributedString
            switch config.text {
            case .text(let text):
                attributedString = NSMutableAttributedString(string: text)
            case .attributedText(let attributedText):
                attributedString = NSMutableAttributedString(attributedString: attributedText)
            case .messageBody(let messageBody):
                let attributedText = messageBody.asAttributedStringForDisplay(
                    config: config.displayConfig,
                    isDarkThemeEnabled: Theme.isDarkThemeEnabled
                )
                attributedString = (attributedText as? NSMutableAttributedString) ?? NSMutableAttributedString(attributedString: attributedText)
            }

            // The original attributed string may not have an overall font assigned.
            // Without it, measurement will not be correct. We assign the default font
            // to any ranges that don't currently have a font assigned.
            attributedString.addDefaultAttributeToEntireString(.font, value: config.font)

            // Set a default text color based on the passed in config
            attributedString.addDefaultAttributeToEntireString(.foregroundColor, value: config.textColor)

            CVTextLabel.linkifyData(
                attributedText: attributedString,
                linkifyStyle: config.linkifyStyle,
                items: config.items
            )

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

            textStorage.addAttributes(config.selectionStyling, range: selectedItem.range)

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

            guard let characterIndex = textContainer.characterIndex(
                of: location,
                textStorage: textStorage,
                layoutManager: layoutManager
            ) else {
                return nil
            }

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

extension CVTextLabel.Label: UIDragInteractionDelegate {
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
        case .referencedUser:
            // Dragging is not applicable to referenced users
            return []
        case .unrevealedSpoiler:
            // Dragging is not applicable for spoilers.
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
