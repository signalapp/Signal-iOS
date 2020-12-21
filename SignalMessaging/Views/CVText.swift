//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

private typealias CacheKey = String

public enum CVTextValue: Equatable, Hashable {
    case text(text: String)
    case attributedText(attributedText: NSAttributedString)

    func apply(label: UILabel) {
        switch self {
        case .text(let text):
            label.text = text
        case .attributedText(let attributedText):
            label.attributedText = attributedText
        }
    }

    func apply(textView: UITextView) {
        switch self {
        case .text(let text):
            textView.text = text
        case .attributedText(let attributedText):
            textView.attributedText = attributedText
        }
    }

    public var stringValue: String {
        switch self {
        case .text(let text):
            return text
        case .attributedText(let attributedText):
            return attributedText.string
        }
    }

    var debugDescription: String {
        switch self {
        case .text(let text):
            return "text: \(text)"
        case .attributedText(let attributedText):
            return "attributedText: \(attributedText.string)"
        }
    }

    fileprivate var cacheKey: CacheKey {
        switch self {
        case .text(let text):
            return "t\(text)"
        case .attributedText(let attributedText):
            return "a\(attributedText.description)"
        }
    }
}

// MARK: - UILabel

public struct CVLabelConfig {

    fileprivate let text: CVTextValue
    public let font: UIFont
    public let textColor: UIColor
    public let numberOfLines: Int
    public let lineBreakMode: NSLineBreakMode
    public let textAlignment: NSTextAlignment?

    public init(text: String,
                font: UIFont,
                textColor: UIColor,
                numberOfLines: Int = 1,
                lineBreakMode: NSLineBreakMode = .byWordWrapping,
                textAlignment: NSTextAlignment? = nil) {

        self.text = .text(text: text)
        self.font = font
        self.textColor = textColor
        self.numberOfLines = numberOfLines
        self.lineBreakMode = lineBreakMode
        self.textAlignment = textAlignment
    }

    public init(attributedText: NSAttributedString,
                font: UIFont,
                textColor: UIColor,
                numberOfLines: Int = 1,
                lineBreakMode: NSLineBreakMode = .byWordWrapping,
                textAlignment: NSTextAlignment? = nil) {

        self.text = .attributedText(attributedText: attributedText)
        self.font = font
        self.textColor = textColor
        self.numberOfLines = numberOfLines
        self.lineBreakMode = lineBreakMode
        self.textAlignment = textAlignment
    }

    func applyForMeasurement(label: UILabel) {
        label.font = self.font
        label.numberOfLines = self.numberOfLines
        label.lineBreakMode = self.lineBreakMode

        // Skip textColor, textAlignment.

        // Apply text last, to protect attributed text attributes.
        // There are also perf benefits.
        self.text.apply(label: label)
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
        self.text.apply(label: label)
    }

    public func measure(maxWidth: CGFloat) -> CGSize {
        CVText.measureLabel(config: self, maxWidth: maxWidth)
    }

    public var stringValue: String {
        text.stringValue
    }

    public var debugDescription: String {
        "CVLabelConfig: \(text.debugDescription)"
    }

    fileprivate var cacheKey: CacheKey {
        // textColor doesn't affect measurement.
        "\(text.cacheKey),\(font.fontName),\(font.pointSize),\(numberOfLines),\(lineBreakMode.rawValue),\(textAlignment?.rawValue ?? 0)"
    }
}

// MARK: - UITextView

public struct CVTextViewConfig {

    fileprivate let text: CVTextValue
    public let font: UIFont
    public let textColor: UIColor
    public let textAlignment: NSTextAlignment?
    public let linkTextAttributes: [NSAttributedString.Key: Any]?

    public init(text: String,
                font: UIFont,
                textColor: UIColor,
                textAlignment: NSTextAlignment? = nil,
                linkTextAttributes: [NSAttributedString.Key: Any]? = nil) {

        self.text = .text(text: text)
        self.font = font
        self.textColor = textColor
        self.textAlignment = textAlignment
        self.linkTextAttributes = linkTextAttributes
    }

    public init(attributedText: NSAttributedString,
                font: UIFont,
                textColor: UIColor,
                textAlignment: NSTextAlignment? = nil,
                linkTextAttributes: [NSAttributedString.Key: Any]? = nil) {

        self.text = .attributedText(attributedText: attributedText)
        self.font = font
        self.textColor = textColor
        self.textAlignment = textAlignment
        self.linkTextAttributes = linkTextAttributes
    }

    func applyForMeasurement(textView: UITextView) {
        textView.font = self.font
        if let linkTextAttributes = linkTextAttributes {
            textView.linkTextAttributes = linkTextAttributes
        }

        // Skip textColor, textAlignment.

        // Apply text last, to protect attributed text attributes.
        // There are also perf benefits.
        self.text.apply(textView: textView)
    }

    public func applyForRendering(textView: UITextView) {
        textView.font = self.font
        textView.textColor = self.textColor
        if let textAlignment = textAlignment {
            textView.textAlignment = textAlignment
        } else {
            textView.textAlignment = .natural
        }
        if let linkTextAttributes = linkTextAttributes {
            textView.linkTextAttributes = linkTextAttributes
        } else {
            textView.linkTextAttributes = [:]
        }

        // Apply text last, to protect attributed text attributes.
        // There are also perf benefits.
        self.text.apply(textView: textView)
    }

    public func measure(maxWidth: CGFloat) -> CGSize {
        CVText.measureTextView(config: self, maxWidth: maxWidth)
    }

    public var stringValue: String {
        text.stringValue
    }

    public var debugDescription: String {
        "CVTextViewConfig: \(text.debugDescription)"
    }

    fileprivate var cacheKey: CacheKey {
        // textColor and linkTextAttributes (for the attributes we set)
        // don't affect measurement.
        "\(text.cacheKey),\(font.fontName),\(font.pointSize),\(textAlignment?.rawValue ?? 0)"
    }
}

// MARK: -

public class CVText {
    public enum MeasurementMode { case view, layoutManager }

    public static var measurementQueue: DispatchQueue { CVUtils.workQueue }

    private static var reuseLabels: Bool {
        false
    }
    public static var defaultLabelMeasurementMode: MeasurementMode {
        .layoutManager
    }

    private static var reuseTextViews: Bool {
        false
    }
    public static var defaultTextViewMeasurementMode: MeasurementMode {
        .layoutManager
    }

    private static var cacheMeasurements = true

    private static let cacheSize: Int = 500

    // MARK: - UILabel

    private static let label_main = UILabel()
    private static let label_workQueue = UILabel()
    private static var labelForMeasurement: UILabel {
        guard reuseLabels else {
            return UILabel()
        }

        if Thread.isMainThread {
            return label_main
        } else {
            if !CurrentAppContext().isRunningTests {
                assertOnQueue(measurementQueue)
            }

            return label_workQueue
        }
    }

    private static func buildCacheKey(configKey: String, maxWidth: CGFloat) -> CacheKey {
        "\(configKey),\(maxWidth)"
    }
    private static let labelCache = LRUCache<CacheKey, CGSize>(maxSize: cacheSize)
    private static let unfairLock = UnfairLock()

    public static func measureLabel(mode: MeasurementMode = defaultLabelMeasurementMode, config: CVLabelConfig, maxWidth: CGFloat) -> CGSize {
        unfairLock.withLock {
            measureLabelLocked(mode: mode, config: config, maxWidth: maxWidth)
        }
    }

    private static func measureLabelLocked(mode: MeasurementMode = defaultLabelMeasurementMode, config: CVLabelConfig, maxWidth: CGFloat) -> CGSize {
        let cacheKey = buildCacheKey(configKey: config.cacheKey, maxWidth: maxWidth)
        if cacheMeasurements,
           let result = labelCache.get(key: cacheKey) {
            return result
        }

        let result: CGSize
        switch mode {
        case .layoutManager:
            result = measureLabelUsingLayoutManager(config: config, maxWidth: maxWidth)
        case .view:
            result = measureLabelUsingView(config: config, maxWidth: maxWidth)
        }
        owsAssertDebug(result.width > 0)
        owsAssertDebug(result.height > 0)

        if cacheMeasurements {
            labelCache.set(key: cacheKey, value: result.ceil)
        }

        return result.ceil
    }

    private static func measureLabelUsingView(config: CVLabelConfig, maxWidth: CGFloat) -> CGSize {
        let label = labelForMeasurement
        config.applyForMeasurement(label: label)
        var size = label.sizeThatFits(CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)).ceil
        // Truncate to available space if necessary.
        size.width = min(size.width, maxWidth)
        return size
    }

    private static func measureLabelUsingLayoutManager(config: CVLabelConfig, maxWidth: CGFloat) -> CGSize {
        let textContainer = NSTextContainer(size: CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        textContainer.maximumNumberOfLines = config.numberOfLines
        textContainer.lineBreakMode = config.lineBreakMode
        textContainer.lineFragmentPadding = 0

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        // NSTextStorage *must* be initialized with `NSOriginalFont` defined,
        // otherwise measurement of character sets that San Francisco doesn't
        // support (CJK, Arabic, etc.) will not measure correctly.
        let textStorage: NSTextStorage
        switch config.text {
        case .attributedText(let text):
            // In order for the `NSOriginalFont` attribute to be retained,
            // the text must be assigned to the NSTextStorage *after* it
            // has been associated with a layout manager.
            textStorage = NSTextStorage(string: "", attributes: [.font: config.font, .originalFont: config.font])
            textStorage.addLayoutManager(layoutManager)
            textStorage.setAttributedString(text)
        case .text(let text):
            textStorage = NSTextStorage(string: text, attributes: [.font: config.font, .originalFont: config.font])
            textStorage.addLayoutManager(layoutManager)
        }

        let size = layoutManager.usedRect(for: textContainer).size

        // For some reason, in production builds, the textStorage
        // seems to get optimized out in many circumstances. This
        // results in `usedRect` measuring an empty string and a
        // size of 0,0.
        // TODO: Figure out a better way to fix this. For now,
        // by just using the textStorage later it ensures that it
        // is properly measured.
        _ = textStorage

        return size.ceil
    }

    // MARK: - UITextView

    private static let textView_main = {
        buildTextView()
    }()
    private static let textView_workQueue = {
        buildTextView()
    }()
    private static var textViewForMeasurement: UITextView {
        guard reuseTextViews else {
            return buildTextView()
        }

        if Thread.isMainThread {
            return textView_main
        } else {
            if !CurrentAppContext().isRunningTests {
                assertOnQueue(measurementQueue)
            }

            return textView_workQueue
        }
    }

    private static let textViewCache = LRUCache<CacheKey, CGSize>(maxSize: cacheSize)

    public static func measureTextView(mode: MeasurementMode = defaultTextViewMeasurementMode,
                                       config: CVTextViewConfig,
                                       maxWidth: CGFloat) -> CGSize {
        unfairLock.withLock {
            measureTextViewLocked(mode: mode, config: config, maxWidth: maxWidth)
        }
    }

    private static func measureTextViewLocked(mode: MeasurementMode = defaultTextViewMeasurementMode,
                                              config: CVTextViewConfig,
                                              maxWidth: CGFloat) -> CGSize {
        let cacheKey = buildCacheKey(configKey: config.cacheKey, maxWidth: maxWidth)
        if cacheMeasurements,
           let result = textViewCache.get(key: cacheKey) {
            return result
        }

        let result: CGSize
        switch mode {
        case .layoutManager:
            result = measureTextViewUsingLayoutManager(config: config, maxWidth: maxWidth)
        case .view:
            result = measureTextViewUsingView(config: config, maxWidth: maxWidth)
        }
        owsAssertDebug(result.width > 0)
        owsAssertDebug(result.height > 0)

        if cacheMeasurements {
            textViewCache.set(key: cacheKey, value: result.ceil)
        }

        return result.ceil
    }

    private static func measureTextViewUsingView(config: CVTextViewConfig, maxWidth: CGFloat) -> CGSize {
        let textView = textViewForMeasurement
        config.applyForMeasurement(textView: textView)
        return textView.sizeThatFits(CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)).ceil
    }

    private static func measureTextViewUsingLayoutManager(config: CVTextViewConfig, maxWidth: CGFloat) -> CGSize {
        let textContainer = NSTextContainer(size: CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        // NSTextStorage *must* be initialized with `NSOriginalFont` defined,
        // otherwise measurement of character sets that San Francisco doesn't
        // support (CJK, Arabic, etc.) will not measure correctly.
        let textStorage: NSTextStorage
        switch config.text {
        case .attributedText(let text):
            // In order for the `NSOriginalFont` attribute to be retained,
            // the text must be assigned to the NSTextStorage *after* it
            // has been associated with a layout manager.
            textStorage = NSTextStorage(string: "", attributes: [.font: config.font, .originalFont: config.font])
            textStorage.addLayoutManager(layoutManager)
            textStorage.setAttributedString(text)
        case .text(let text):
            textStorage = NSTextStorage(string: text, attributes: [.font: config.font, .originalFont: config.font])
            textStorage.addLayoutManager(layoutManager)
        }

        let size = layoutManager.usedRect(for: textContainer).size

        // For some reason, in production builds, the textStorage
        // seems to get optimized out in many circumstances. This
        // results in `usedRect` measuring an empty string and a
        // size of 0,0.
        // TODO: Figure out a better way to fix this. For now,
        // by just using the textStorage later it ensures that it
        // is properly measured.
        _ = textStorage

        return size.ceil
    }

    public static func buildTextView() -> OWSMessageTextView {
        let textView = OWSMessageTextView()

        textView.backgroundColor = .clear
        textView.isOpaque = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.contentInset = .zero

        return textView
    }
}

private extension NSAttributedString.Key {
    static var originalFont = Self("NSOriginalFont")
}
