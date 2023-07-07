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

    public var fullTextNaturalAlignment: NSTextAlignment {
        return fullContent.naturalAlignment
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
        switch fullContent.textValue {
        case .text(let text):
            self.jumbomojiCount = DisplayableText.jumbomojiCount(in: text)
            self.fullLengthWithNewLineScalar = DisplayableText.fullLengthWithNewLineScalar(in: text)
        case .attributedText(let attributedText):
            self.jumbomojiCount = DisplayableText.jumbomojiCount(in: attributedText.string)
            self.fullLengthWithNewLineScalar = DisplayableText.fullLengthWithNewLineScalar(in: attributedText.string)
        case .messageBody(let messageBody):
            self.jumbomojiCount = messageBody.jumbomojiCount(DisplayableText.jumbomojiCount(in:))
            self.fullLengthWithNewLineScalar = messageBody.fullLengthWithNewLineScalar(DisplayableText.fullLengthWithNewLineScalar(in:))
        }

        super.init()
    }

    #if TESTABLE_BUILD
    internal static func testOnlyInit(fullContent: CVTextValue, truncatedContent: CVTextValue?) -> DisplayableText {
        return DisplayableText.init(
            fullContent: .init(textValue: fullContent, naturalAlignment: fullContent.naturalTextAligment),
            truncatedContent: truncatedContent.map { .init(textValue: $0, naturalAlignment: $0.naturalTextAligment) }
        )
    }
    #endif

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

        func validate(_ rawText: String) -> Bool {
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
        }

        switch fullContent.textValue {
        case .text(let text):
            return validate(text)
        case .attributedText(let attributedText):
            return validate(attributedText.string)
        case .messageBody(let messageBody):
            return messageBody.shouldAllowLinkification(linkDetector: linkDetector, isValidLink: isValidLink(linkText:))
        }
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
            fullContent: .init(textValue: .text(""), naturalAlignment: .natural),
            truncatedContent: nil
        )
    }

    public class func displayableText(
        withMessageBody messageBody: MessageBody,
        transaction: SDSAnyReadTransaction
    ) -> DisplayableText {
        let textValue: CVTextValue
        if messageBody.ranges.hasRanges {
            let hydrated = messageBody
                .hydrating(
                    mentionHydrator: ContactsMentionHydrator.mentionHydrator(transaction: transaction.asV2Read)
                )
            textValue = .messageBody(hydrated)
        } else {
            textValue = .text(messageBody.text)
        }
        let fullContent = Content(
            textValue: textValue,
            naturalAlignment: textValue.naturalTextAligment
        )

        // Only show up to N characters of text.
        let kMaxTextDisplayLength = 512
        let kMaxSnippetNewLines = 15
        let truncatedContent: Content?

        if fullContent.textValue.stringLength > kMaxTextDisplayLength {
            var snippetLength = kMaxTextDisplayLength

            func deriveSnippetLengthForPlaintext(_ text: String) -> Int {
                // Message bubbles by default should be short. We don't ever
                // want to show more than X new lines in the truncated text.
                let newLineMatches = newLineRegex.matches(
                    in: text,
                    options: [],
                    range: NSRange(location: 0, length: kMaxTextDisplayLength)
                )
                if newLineMatches.count > kMaxSnippetNewLines {
                    return newLineMatches[kMaxSnippetNewLines - 1].range.location
                }
                return kMaxTextDisplayLength
            }

            switch textValue {
            case .text(let text):
                snippetLength = deriveSnippetLengthForPlaintext(text)

                let truncatedText = (text.substring(to: snippetLength)
                                        .ows_stripped()
                                        + Self.truncatedTextSuffix)
                truncatedContent = Content(textValue: .text(truncatedText),
                                           naturalAlignment: truncatedText.naturalTextAlignment)
            case .attributedText(let attributedText):
                snippetLength = deriveSnippetLengthForPlaintext(attributedText.string)

                let truncatedText = attributedText
                    .attributedSubstring(from: NSRange(location: 0, length: snippetLength))
                    .ows_stripped()
                    + Self.truncatedTextSuffix
                truncatedContent = Content(
                    textValue: .attributedText(truncatedText),
                    naturalAlignment: truncatedText.string.naturalTextAlignment
                )

            case .messageBody(let messageBody):
                let truncatedBody = messageBody.truncating(desiredLength: snippetLength, truncationSuffix: Self.truncatedTextSuffix)

                truncatedContent = Content(
                    textValue: .messageBody(truncatedBody),
                    naturalAlignment: truncatedBody.naturalTextAlignment
                )
            }
        } else {
            truncatedContent = nil
        }

        return DisplayableText(fullContent: fullContent, truncatedContent: truncatedContent)
    }
}
