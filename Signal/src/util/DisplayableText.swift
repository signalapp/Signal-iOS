//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

public class DisplayableText: NSObject {

    private struct Content {
        let textValue: CVTextValue
        let naturalAlignment: NSTextAlignment

        var stringValue: String { textValue.stringValue }
    }

    private let _fullContent: AtomicValue<Content>
    private var fullContent: Content {
        get { _fullContent.get() }
        set { _fullContent.set(newValue) }
    }

    private let _truncatedContent = AtomicOptional<Content>(nil)
    private var truncatedContent: Content? {
        get { _truncatedContent.get() }
        set { _truncatedContent.set(newValue) }
    }

    public var fullTextValue: CVTextValue {
        fullContent.textValue
    }

    public var truncatedTextValue: CVTextValue? {
        truncatedContent?.textValue
    }

    public var displayTextValue: CVTextValue {
        return truncatedContent?.textValue ?? fullContent.textValue
    }

    public func textValue(isTextExpanded: Bool) -> CVTextValue {
        if isTextExpanded {
            return fullTextValue
        } else {
            return displayTextValue
        }
    }

    public var fullAttributedText: NSAttributedString {
        switch fullContent.textValue {
        case .text(let text):
            return NSAttributedString(string: text)
        case .attributedText(let attributedText):
            return attributedText
        }
    }

    public var fullTextNaturalAlignment: NSTextAlignment {
        return fullContent.naturalAlignment
    }

    @objc
    public var displayAttributedText: NSAttributedString {
        let content = truncatedContent ?? fullContent
        switch content.textValue {
        case .text(let text):
            return NSAttributedString(string: text)
        case .attributedText(let attributedText):
            return attributedText
        }
    }

    @objc
    public var displayTextNaturalAlignment: NSTextAlignment {
        return truncatedContent?.naturalAlignment ?? fullContent.naturalAlignment
    }

    public var isTextTruncated: Bool {
        return truncatedContent != nil
    }

    private static let maxInlineText = 1024 * 8

    public var canRenderTruncatedTextInline: Bool {
        return isTextTruncated && fullLengthWithNewLineScalar <= Self.maxInlineText
    }

    public let fullLengthWithNewLineScalar: Int

    public let jumbomojiCount: UInt

    public static let kMaxJumbomojiCount: Int = 5

    static let truncatedTextSuffix: String = "…"

    // MARK: Initializers

    private init(fullContent: Content, truncatedContent: Content?) {
        self._fullContent = AtomicValue(fullContent)
        self._truncatedContent.set(truncatedContent)
        self.jumbomojiCount = DisplayableText.jumbomojiCount(in: fullContent.stringValue)
        self.fullLengthWithNewLineScalar = DisplayableText.fullLengthWithNewLineScalar(in: fullContent.stringValue)

        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .themeDidChange,
            object: nil
        )
    }

    @objc
    private func themeDidChange() {
        // When the theme changes, we must refresh any mention attributes.
        func updateContent(_ content: Content) -> Content {
            switch content.textValue {
            case .text:
                // We only need to update attributedText.
                return content
            case .attributedText(var attributedText):
                let body = RecoveredHydratedMessageBody.recover(from: attributedText)
                switch body.applyable() {
                case .unconfigured:
                    Logger.debug("Theme changed before body ranges were configured; skipping")
                case .alreadyConfigured(let apply):
                    attributedText = apply(Theme.isDarkThemeEnabled)
                }
                return Content(textValue: .attributedText(attributedText: attributedText),
                               naturalAlignment: content.naturalAlignment)
            }
        }

        // When the theme changes, we must refresh any mention attributes.
        // Note that text formatting styles are also theme dependent but
        // get set along with the rest of the properties applied to the
        // whole text body (e.g. CVComponentBodyText.textViewConfig).
        fullContent = updateContent(fullContent)

        if let truncatedContent = truncatedContent {
            self.truncatedContent = updateContent(truncatedContent)
        }
    }

    // MARK: Emoji

    // If the string...
    //
    // * Contains <= kMaxJumbomojiCount characters
    // * Contains only emoji
    //
    // ...return the number of emoji (to be treated as "Jumbomoji") in the string.
    private class func jumbomojiCount(in string: String) -> UInt {
        // Don't iterate the entire string; only inspect the first few characters.
        let stringPrefix = string.prefix(kMaxJumbomojiCount + 1)
        let emojiCount = stringPrefix.count
        guard emojiCount <= kMaxJumbomojiCount else {
            return 0
        }
        guard string.containsOnlyEmoji else {
            return 0
        }
        return UInt(emojiCount)
    }

    // For perf we use a static linkDetector. It doesn't change and building DataDetectors is
    // surprisingly expensive. This should be fine, since NSDataDetector is an NSRegularExpression
    // and NSRegularExpressions are thread safe.
    private static let linkDetector: NSDataDetector? = {
        return try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    private static let hostRegex: NSRegularExpression? = {
        let pattern = "^(?:https?:\\/\\/)?([^:\\/\\s]+)(.*)?$"
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    public lazy var shouldAllowLinkification: Bool = {
        guard let linkDetector: NSDataDetector = DisplayableText.linkDetector else {
            owsFailDebug("linkDetector was unexpectedly nil")
            return false
        }

        func isValidLink(linkText: String) -> Bool {
            guard let hostRegex = DisplayableText.hostRegex else {
                owsFailDebug("hostRegex was unexpectedly nil")
                return false
            }

            guard let hostText = hostRegex.parseFirstMatch(inText: linkText) else {
                owsFailDebug("hostText was unexpectedly nil")
                return false
            }

            let strippedHost = hostText.replacingOccurrences(of: ".", with: "") as NSString

            if strippedHost.isOnlyASCII {
                return true
            } else if strippedHost.hasAnyASCII {
                // mix of ascii and non-ascii is invalid
                return false
            } else {
                // IDN
                return true
            }
        }

        let rawText = fullContent.stringValue

        guard LinkValidator.canParseURLs(in: rawText) else {
            return false
        }

        for match in linkDetector.matches(in: rawText, options: [], range: rawText.entireRange) {
            guard let matchURL: URL = match.url else {
                continue
            }

            // We extract the exact text from the `fullText` rather than use match.url.host
            // because match.url.host actually escapes non-ascii domains into puny-code.
            //
            // But what we really want is to check the text which will ultimately be presented to
            // the user.
            let rawTextOfMatch = (rawText as NSString).substring(with: match.range)
            guard isValidLink(linkText: rawTextOfMatch) else {
                return false
            }
        }
        return true
    }()

    // MARK: Filter Methods

    private static let newLineRegex = try! NSRegularExpression(pattern: "\n", options: [])
    private static let newLineScalar = 16

    private class func fullLengthWithNewLineScalar(in string: String) -> Int {
        let numberOfNewLines = newLineRegex.numberOfMatches(
            in: string,
            options: [],
            range: string.entireRange
        )
        return string.utf16.count + numberOfNewLines * newLineScalar
    }

    public class var empty: DisplayableText {
        return DisplayableText(
            fullContent: .init(textValue: .text(text: ""), naturalAlignment: .natural),
            truncatedContent: nil
        )
    }

    public class func displayableTextForTests(_ text: String) -> DisplayableText {
        return DisplayableText(
            fullContent: .init(textValue: .text(text: text),
                               naturalAlignment: text.naturalTextAlignment),
            truncatedContent: nil
        )
    }

    public class func displayableText(
        withMessageBody messageBody: MessageBody,
        displayConfig: HydratedMessageBody.DisplayConfiguration,
        transaction: SDSAnyReadTransaction
    ) -> DisplayableText {
        let textValue: CVTextValue
        if messageBody.ranges.hasRanges {
            let attributedString = messageBody
                .hydrating(
                    mentionHydrator: ContactsMentionHydrator.mentionHydrator(transaction: transaction.asV2Read)
                )
                .asAttributedStringForDisplay(config: displayConfig, isDarkThemeEnabled: Theme.isDarkThemeEnabled)
            textValue = .attributedText(attributedText: attributedString)
        } else {
            textValue = .text(text: messageBody.text)
        }
        let fullContent = Content(
            textValue: textValue,
            naturalAlignment: textValue.stringValue.naturalTextAlignment
        )

        // Only show up to N characters of text.
        let kMaxTextDisplayLength = 512
        let kMaxSnippetNewLines = 15
        let truncatedContent: Content?

        if fullContent.stringValue.count > kMaxTextDisplayLength {
            var snippetLength = kMaxTextDisplayLength

            // Message bubbles by default should be short. We don't ever
            // want to show more than X new lines in the truncated text.
            let newLineMatches = newLineRegex.matches(
                in: fullContent.stringValue,
                options: [],
                range: NSRange(location: 0, length: kMaxTextDisplayLength)
            )
            if newLineMatches.count > kMaxSnippetNewLines {
                snippetLength = newLineMatches[kMaxSnippetNewLines - 1].range.location
            }

            switch textValue {
            case .text(let text):
                let truncatedText = (text.substring(to: snippetLength)
                                        .ows_stripped()
                                        + Self.truncatedTextSuffix)
                truncatedContent = Content(textValue: .text(text: truncatedText),
                                           naturalAlignment: truncatedText.naturalTextAlignment)
            case .attributedText(let attributedText):
                let mentionRanges = RecoveredHydratedMessageBody.recover(
                    from: NSMutableAttributedString(attributedString: attributedText)
                ).mentions()
                var possibleOverlappingMention: NSRange?
                for (candidateRange, _) in mentionRanges {
                    if candidateRange.contains(snippetLength) {
                        possibleOverlappingMention = candidateRange
                        break
                    }
                    if candidateRange.location > snippetLength {
                        // mentions are ordered; can early exit if we pass it.
                        break
                    }
                }

                // There's a mention overlapping our normal truncate point, we want to truncate sooner
                // so we don't "split" the mention.
                if let possibleOverlappingMention, possibleOverlappingMention.location < snippetLength {
                    snippetLength = possibleOverlappingMention.location
                }

                // Trim whitespace before _AND_ after slicing the snippet from the string.
                let truncatedAttributedText = attributedText
                    .attributedSubstring(from: NSRange(location: 0, length: snippetLength))
                    .ows_stripped()
                    .stringByAppendingString(Self.truncatedTextSuffix)

                truncatedContent = Content(textValue: .attributedText(attributedText: truncatedAttributedText),
                                           naturalAlignment: truncatedAttributedText.string.naturalTextAlignment)
            }
        } else {
            truncatedContent = nil
        }

        return DisplayableText(fullContent: fullContent, truncatedContent: truncatedContent)
    }
}
