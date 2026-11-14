//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum LinkValidator {
    public static func canParseURLs(in entireMessage: String) -> Bool {
        if entireMessage.unicodeScalars.contains(where: isProblematicCodepointAnywhereInString(_:)) {
            return false
        }
        return true
    }

    public static func isValidLink(linkText: String) -> Bool {
        if linkText.unicodeScalars.contains(where: isProblematicCodepointInLink(_:)) {
            return false
        }
        return true
    }

    private static func isProblematicCodepointAnywhereInString(_ scalar: UnicodeScalar) -> Bool {
        switch scalar {
        case "\u{202C}", // POP DIRECTIONAL FORMATTING
             "\u{202D}", // LEFT-TO-RIGHT OVERRIDE
             "\u{202E}": // RIGHT-TO-LEFT OVERRIDE
            return true
        default:
            return false
        }
    }

    private static func isProblematicCodepointInLink(_ scalar: UnicodeScalar) -> Bool {
        if isProblematicCodepointAnywhereInString(scalar) {
            return true
        }
        switch scalar {
        case "\u{2500}"..."\u{25FF}": // Box Drawing, Block Elements, Geometric Shapes
            return true
        default:
            return false
        }
    }

    public static func firstLinkPreviewURL(in entireMessage: MessageBody) -> URL? {
        var result: URL?
        enumerateLinkPreviewURLs(in: entireMessage) { url, _, stop in
            result = url
            stop = true
        }
        return result
    }

    /// Whether `urlString` is verbatim a link preview URL in `messageBody`.
    public static func containsLinkPreviewURL(
        _ urlString: String,
        messageBody: MessageBody,
    ) -> Bool {
        var result = false
        enumerateLinkPreviewURLs(in: messageBody) { _, matchedText, stop in
            if matchedText == urlString {
                result = true
                stop = true
            }
        }
        return result
    }

    private static func enumerateLinkPreviewURLs(
        in entireMessage: MessageBody,
        block: (_ url: URL, _ matchedText: String, _ stop: inout Bool) -> Void,
    ) {
        // Don't include link previews for oversize text messages.
        guard entireMessage.text.utf8.dropFirst(OWSMediaUtils.kOversizeTextMessageSizeThresholdBytes).isEmpty else {
            return
        }

        guard canParseURLs(in: entireMessage.text) else {
            return
        }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            owsFailDebug("Could not create NSDataDetector")
            return
        }

        detector.enumerateMatches(
            in: entireMessage.text,
            range: entireMessage.text.entireRange,
        ) { match, _, stop in
            guard
                let match,
                let parsedUrl = match.url,
                let matchedRange = Range(match.range, in: entireMessage.text)
            else {
                return
            }

            // No previews for spoilered URLs
            for style in entireMessage.ranges.collapsedStyles {
                if
                    style.value.style.contains(style: .spoiler),
                    style.range.intersection(match.range)?.location ?? NSNotFound != NSNotFound
                {
                    return
                }
                // Styles are ordered; no need to search past the matched range.
                if style.range.lowerBound >= match.range.upperBound {
                    break
                }
            }

            let matchedText = String(entireMessage.text[matchedRange])
            guard
                LinkPreviewHelper.isPermittedLinkPreviewUrl(
                    parsedUrl,
                    parsedFrom: matchedText,
                )
            else {
                return
            }

            var shouldStop = false
            block(parsedUrl, matchedText, &shouldStop)
            stop.pointee = ObjCBool(shouldStop)
        }
    }
}
