//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public enum CVTextValue: Equatable, Hashable {
    public typealias CacheKey = String

    case text(String)
    case attributedText(NSAttributedString)
    case messageBody(HydratedMessageBody)

    public var isEmpty: Bool {
        switch self {
        case .text(let text):
            return text.isEmpty
        case .attributedText(let attributedText):
            return attributedText.isEmpty
        case .messageBody(let messageBody):
            return messageBody.isEmpty
        }
    }

    public var nilIfEmpty: CVTextValue? {
        return self.isEmpty ? nil : self
    }

    public var stringLength: Int {
        switch self {
        case .text(let text):
            return (text as NSString).length
        case .attributedText(let attributedText):
            return attributedText.length
        case .messageBody(let hydratedMessageBody):
            return hydratedMessageBody.rawTextLength
        }
    }

    public var naturalTextAligment: NSTextAlignment {
        switch self {
        case .text(let text):
            return text.naturalTextAlignment
        case .attributedText(let attributedText):
            return attributedText.string.naturalTextAlignment
        case .messageBody(let hydratedMessageBody):
            return hydratedMessageBody.naturalTextAlignment
        }
    }

    public var accessibilityDescription: String {
        switch self {
        case .text(let text):
            return text
        case .attributedText(let attributedText):
            return attributedText.string
        case .messageBody(let hydratedMessageBody):
            return hydratedMessageBody.accessibilityDescription
        }
    }

    var debugDescription: String {
        switch self {
        case .text(let text):
            return "text: \(text)"
        case .attributedText(let attributedText):
            return "attributedText: \(attributedText.string)"
        case .messageBody(let messageBody):
            return "messageBody: \(messageBody.debugDescription)"
        }
    }

    public var cacheKey: CacheKey {
        switch self {
        case .text(let text):
            return "t\(text)"
        case .attributedText(let attributedText):
            return "a\(attributedText.description)"
        case .messageBody(let messageBody):
            return "m\(messageBody.cacheKey)"
        }
    }
}

// MARK: - UILabel

public struct CVLabelConfig {
    public typealias CacheKey = String

    public let text: CVTextValue
    public let displayConfig: HydratedMessageBody.DisplayConfiguration
    public let font: UIFont
    public let textColor: UIColor
    public let numberOfLines: Int
    public let lineBreakMode: NSLineBreakMode
    public let textAlignment: NSTextAlignment?

    public init(
        text: CVTextValue,
        displayConfig: HydratedMessageBody.DisplayConfiguration,
        font: UIFont,
        textColor: UIColor,
        numberOfLines: Int = 1,
        lineBreakMode: NSLineBreakMode = .byWordWrapping,
        textAlignment: NSTextAlignment? = nil
    ) {
        self.text = text
        self.displayConfig = displayConfig
        self.font = font
        self.textColor = textColor
        self.numberOfLines = numberOfLines
        self.lineBreakMode = lineBreakMode
        self.textAlignment = textAlignment
    }

    public static func unstyledText(
        _ text: String,
        font: UIFont,
        textColor: UIColor,
        numberOfLines: Int = 1,
        lineBreakMode: NSLineBreakMode = .byWordWrapping,
        textAlignment: NSTextAlignment? = nil
    ) -> Self {
        return .init(
            text: .text(text),
            displayConfig: .forUnstyledText(font: font, textColor: textColor),
            font: font,
            textColor: textColor,
            numberOfLines: numberOfLines,
            lineBreakMode: lineBreakMode,
            textAlignment: textAlignment
        )
    }

    func applyForMeasurement(label: UILabel) {
        label.font = self.font
        label.numberOfLines = self.numberOfLines
        label.lineBreakMode = self.lineBreakMode

        // Skip textColor, textAlignment.

        // Apply text last, to protect attributed text attributes.
        // There are also perf benefits.
        switch text {
        case .text(let text):
            label.text = text
        case .attributedText(let attributedText):
            label.attributedText = attributedText
        case .messageBody(let hydratedMessageBody):
            label.attributedText = hydratedMessageBody.asAttributedStringForDisplay(
                config: displayConfig,
                isDarkThemeEnabled: false /* irrelevant, measuring */
            )
        }
    }

    public func applyForRendering(label: UILabel) {
        label.font = self.font
        label.numberOfLines = self.numberOfLines
        label.lineBreakMode = self.lineBreakMode
        label.textColor = self.textColor
        if let textAlignment = textAlignment {
            label.textAlignment = textAlignment
        } else {
            label.textAlignment = .natural
        }

        // Apply text last, to protect attributed text attributes.
        // There are also perf benefits.
        switch text {
        case .text(let text):
            label.text = text
        case .attributedText(let attributedText):
            label.attributedText = attributedText
        case .messageBody(let hydratedMessageBody):
            label.attributedText = hydratedMessageBody.asAttributedStringForDisplay(
                config: self.displayConfig,
                isDarkThemeEnabled: Theme.isDarkThemeEnabled
            )
        }
    }

    public func measure(maxWidth: CGFloat) -> CGSize {
        let size = CVText.measureLabel(config: self, maxWidth: maxWidth)
        if size.width > maxWidth {
            owsFailDebug("size.width: \(size.width) > maxWidth: \(maxWidth)")
        }
        return size
    }

    public var debugDescription: String {
        "CVLabelConfig: \(text.debugDescription)"
    }

    public var cacheKey: CacheKey {
        // textColor doesn't affect measurement.
        "\(text.cacheKey),\(font.fontName),\(font.pointSize),\(numberOfLines),\(lineBreakMode.rawValue),\(textAlignment?.rawValue ?? 0)"
    }
}

// MARK: - UITextView

public struct CVTextViewConfig {

    public enum LinkifyStyle {
        case linkAttribute
        case underlined(bodyTextColor: UIColor)
    }

    public typealias CacheKey = String

    public let text: CVTextValue
    public let font: UIFont
    public let textColor: UIColor
    public let textAlignment: NSTextAlignment?
    public let displayConfiguration: HydratedMessageBody.DisplayConfiguration
    public let linkTextAttributes: [NSAttributedString.Key: Any]?
    public let linkifyStyle: LinkifyStyle
    public let linkItems: [CVTextLabel.Item]
    public let matchedSearchRanges: [NSRange]
    public let extraCacheKeyFactors: [String]?

    public init(
        text: CVTextValue,
        font: UIFont,
        textColor: UIColor,
        textAlignment: NSTextAlignment? = nil,
        displayConfiguration: HydratedMessageBody.DisplayConfiguration,
        linkTextAttributes: [NSAttributedString.Key: Any]? = nil,
        linkifyStyle: LinkifyStyle,
        linkItems: [CVTextLabel.Item],
        matchedSearchRanges: [NSRange],
        extraCacheKeyFactors: [String]? = nil
    ) {

        self.text = text
        self.font = font
        self.textColor = textColor
        self.textAlignment = textAlignment
        self.displayConfiguration = displayConfiguration
        self.linkTextAttributes = linkTextAttributes
        self.linkifyStyle = linkifyStyle
        self.linkItems = linkItems
        self.matchedSearchRanges = matchedSearchRanges
        self.extraCacheKeyFactors = extraCacheKeyFactors
    }

    public var debugDescription: String {
        "CVTextViewConfig: \(text.debugDescription)"
    }

    public var cacheKey: CacheKey {
        // textColor link-related attributes and search ranges (for the attributes we set)
        // don't affect measurement.
        var cacheKey = "\(text.cacheKey),\(font.fontName),\(font.pointSize),\(textAlignment?.rawValue ?? 0)"

        if let extraCacheKeyFactors = self.extraCacheKeyFactors {
            cacheKey += extraCacheKeyFactors.joined(separator: ",")
        }

        return cacheKey
    }
}

// MARK: -

public class CVText {
    public typealias CacheKey = String

    private static var cacheMeasurements = true

    private static let cacheSize: Int = 500

    // MARK: - UILabel

    private static func buildCacheKey(configKey: String, maxWidth: CGFloat) -> CacheKey {
        "\(configKey),\(maxWidth)"
    }
    private static let labelCache = LRUCache<CacheKey, CGSize>(maxSize: cacheSize)

    public static func measureLabel(config: CVLabelConfig, maxWidth: CGFloat) -> CGSize {
        let cacheKey = buildCacheKey(configKey: config.cacheKey, maxWidth: maxWidth)
        if cacheMeasurements,
           let result = labelCache.get(key: cacheKey) {
            return result
        }

        let result = measureLabelUsingLayoutManager(config: config, maxWidth: maxWidth)
        owsAssertDebug(result.isNonEmpty || config.text.isEmpty)

        if cacheMeasurements {
            labelCache.set(key: cacheKey, value: result.ceil)
        }

        return result.ceil
    }

    #if TESTABLE_BUILD
    public static func measureLabelUsingView(config: CVLabelConfig, maxWidth: CGFloat) -> CGSize {
        guard !config.text.isEmpty else {
            return .zero
        }
        let label = UILabel()
        config.applyForMeasurement(label: label)
        var size = label.sizeThatFits(CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)).ceil
        // Truncate to available space if necessary.
        size.width = min(size.width, maxWidth)
        return size
    }
    #endif

    static func measureLabelUsingLayoutManager(config: CVLabelConfig, maxWidth: CGFloat) -> CGSize {
        guard !config.text.isEmpty else {
            return .zero
        }
        let textContainer = NSTextContainer(size: CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        textContainer.maximumNumberOfLines = config.numberOfLines
        textContainer.lineBreakMode = config.lineBreakMode
        textContainer.lineFragmentPadding = 0
        return textContainer.size(for: config.text, font: config.font)
    }

    // MARK: - CVTextLabel

    private static let bodyTextLabelCache = LRUCache<CacheKey, CVTextLabel.Measurement>(maxSize: cacheSize)

    public static func measureBodyTextLabel(config: CVTextLabel.Config, maxWidth: CGFloat) -> CVTextLabel.Measurement {
        let cacheKey = buildCacheKey(configKey: config.cacheKey, maxWidth: maxWidth)
        if cacheMeasurements,
           let result = bodyTextLabelCache.get(key: cacheKey) {
            return result
        }

        let measurement = CVTextLabel.measureSize(config: config, maxWidth: maxWidth)
        owsAssertDebug(measurement.size.width > 0)
        owsAssertDebug(measurement.size.height > 0)
        owsAssertDebug(measurement.size == measurement.size.ceil)

        if cacheMeasurements {
            bodyTextLabelCache.set(key: cacheKey, value: measurement)
        }

        return measurement
    }
}

// MARK: -

private extension NSTextContainer {
    func size(for textValue: CVTextValue, font: UIFont) -> CGSize {
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(self)

        let attributedString: NSAttributedString
        switch textValue {
        case .messageBody(let messageBody):
            attributedString = messageBody.asAttributedStringForDisplay(
                config: .forMeasurement(font: font),
                isDarkThemeEnabled: false /* doesn't matter */
            )
        case .attributedText(let text):
            let mutableText = NSMutableAttributedString(attributedString: text)
            // The original attributed string may not have an overall font assigned.
            // Without it, measurement will not be correct. We assign the default font
            // to any ranges that don't currently have a font assigned.
            mutableText.addDefaultAttributeToEntireString(.font, value: font)
            attributedString = mutableText
        case .text(let text):
            attributedString = NSAttributedString(string: text, attributes: [.font: font])
        }

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
        let size = withExtendedLifetime(textStorage) { layoutManager.usedRect(for: self).size }

        return size.ceil
    }
}
