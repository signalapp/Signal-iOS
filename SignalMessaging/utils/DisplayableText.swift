//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc public class DisplayableText: NSObject {

    private struct Content {
        let text: String
        let naturalAlignment: NSTextAlignment
    }

    private let fullContent: Content
    private let truncatedContent: Content?

    @objc
    public var fullText: String {
        return fullContent.text
    }

    @objc
    public var fullTextNaturalAlignment: NSTextAlignment {
        return fullContent.naturalAlignment
    }

    @objc
    public var displayText: String {
        return truncatedContent?.text ?? fullContent.text
    }

    @objc
    public var displayTextNaturalAlignment: NSTextAlignment {
        return truncatedContent?.naturalAlignment ?? fullContent.naturalAlignment
    }

    @objc
    public var isTextTruncated: Bool {
        return truncatedContent != nil
    }

    @objc public let jumbomojiCount: UInt

    @objc
    static let kMaxJumbomojiCount: UInt = 5

    // This value is a bit arbitrary since we don't need to be 100% correct about 
    // rendering "Jumbomoji".  It allows us to place an upper bound on worst-case
    // performacne.
    @objc
    static let kMaxCharactersPerEmojiCount: UInt = 10

    // MARK: Initializers

    private init(fullContent: Content, truncatedContent: Content?) {
        self.fullContent = fullContent
        self.truncatedContent = truncatedContent
        self.jumbomojiCount = DisplayableText.jumbomojiCount(in: fullContent.text)
    }

    // MARK: Emoji

    // If the string is...
    //
    // * Non-empty
    // * Only contains emoji
    // * Contains <= kMaxJumbomojiCount emoji
    //
    // ...return the number of emoji (to be treated as "Jumbomoji") in the string.
    private class func jumbomojiCount(in string: String) -> UInt {
        if string == "" {
            return 0
        }
        if string.count > Int(kMaxJumbomojiCount * kMaxCharactersPerEmojiCount) {
            return 0
        }
        guard string.containsOnlyEmoji else {
            return 0
        }
        let emojiCount = string.glyphCount
        if UInt(emojiCount) > kMaxJumbomojiCount {
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
        return try? NSRegularExpression(pattern: pattern)
    }()

    @objc
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

        for match in linkDetector.matches(in: fullText, options: [], range: NSRange(location: 0, length: fullText.utf16.count)) {
            guard let matchURL: URL = match.url else {
                continue
            }

            // We extract the exact text from the `fullText` rather than use match.url.host
            // because match.url.host actually escapes non-ascii domains into puny-code.
            //
            // But what we really want is to check the text which will ultimately be presented to
            // the user.
            let rawTextOfMatch = (fullText as NSString).substring(with: match.range)
            guard isValidLink(linkText: rawTextOfMatch) else {
                return false
            }
        }
        return true
    }()

    // MARK: Filter Methods

    @objc
    public class func displayableText(_ rawText: String) -> DisplayableText {
        let fullText = rawText.filterStringForDisplay()
        let fullContent = Content(text: fullText, naturalAlignment: fullText.naturalTextAlignment)

        // Only show up to N characters of text.
        let kMaxTextDisplayLength = 512
        let truncatedContent: Content?
        if fullText.count > kMaxTextDisplayLength {
            // Trim whitespace before _AND_ after slicing the snipper from the string.
            let snippet = fullText.safePrefix(kMaxTextDisplayLength).ows_stripped()
            let truncatedText = String(format: NSLocalizedString("OVERSIZE_TEXT_DISPLAY_FORMAT", comment:
                "A display format for oversize text messages."),
                snippet)
            truncatedContent = Content(text: truncatedText, naturalAlignment: truncatedText.naturalTextAlignment)
        } else {
            truncatedContent = nil
        }

        return DisplayableText(fullContent: fullContent, truncatedContent: truncatedContent)
    }
}
