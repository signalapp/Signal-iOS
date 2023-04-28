//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum LinkValidator {
    public static func canParseURLs(in entireMessage: String) -> Bool {
        if entireMessage.unicodeScalars.contains(where: isProblematicCodepoint(_:)) {
            return false
        }
        return true
    }

    private static func isProblematicCodepoint(_ scalar: UnicodeScalar) -> Bool {
        switch scalar {
        case "\u{202C}", // POP DIRECTIONAL FORMATTING
            "\u{202D}", // LEFT-TO-RIGHT OVERRIDE
            "\u{202E}": // RIGHT-TO-LEFT OVERRIDE
            return true
        case "\u{2500}"..."\u{25FF}": // Box Drawing, Block Elements, Geometric Shapes
            return true
        default:
            return false
        }
    }

    public static func firstLinkPreviewURL(in entireMessage: String) -> URL? {
        // Don't include link previews for oversize text messages.
        guard entireMessage.utf8.dropFirst(Int(kOversizeTextMessageSizeThreshold) - 1).isEmpty else {
            return nil
        }

        guard canParseURLs(in: entireMessage) else {
            return nil
        }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            owsFailDebug("Could not create NSDataDetector")
            return nil
        }

        var result: URL?
        detector.enumerateMatches(in: entireMessage, range: entireMessage.entireRange) { match, _, stop in
            guard let match = match else { return }
            guard let parsedUrl = match.url else { return }
            guard let matchedRange = Range(match.range, in: entireMessage) else { return }
            guard parsedUrl.absoluteString.isEmpty.negated else { return }
            guard parsedUrl.isPermittedLinkPreviewUrl(parsedFrom: String(entireMessage[matchedRange])) else { return }
            result = parsedUrl
            stop.pointee = true
        }
        return result
    }
}
