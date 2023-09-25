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
        // Don't include link previews for oversize text messages.
        guard entireMessage.text.utf8.dropFirst(Int(kOversizeTextMessageSizeThreshold) - 1).isEmpty else {
            return nil
        }

        guard canParseURLs(in: entireMessage.text) else {
            return nil
        }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            owsFailDebug("Could not create NSDataDetector")
            return nil
        }

        var result: URL?
        detector.enumerateMatches(
            in: entireMessage.text,
            range: entireMessage.text.entireRange
        ) { match, _, stop in
            guard let match = match else { return }
            guard let parsedUrl = match.url else { return }
            guard let matchedRange = Range(match.range, in: entireMessage.text) else { return }
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
            guard parsedUrl.absoluteString.isEmpty.negated else { return }
            guard parsedUrl.isPermittedLinkPreviewUrl(parsedFrom: String(entireMessage.text[matchedRange])) else { return }
            result = parsedUrl
            stop.pointee = true
        }
        return result
    }
}
