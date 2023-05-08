//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import CocoaLumberjack
import SignalServiceKit

@objc
class OWSScrubbingLogFormatter: DDLogFileFormatterDefault {
    private struct Replacement {
        let regex: NSRegularExpression
        let replacementTemplate: String

        init(
            pattern: String,
            options: NSRegularExpression.Options = [],
            replacementTemplate: String
        ) {
            do {
                self.regex = try .init(pattern: pattern, options: options)
            } catch {
                owsFail("Could not compile regular expression: \(error)")
            }
            self.replacementTemplate = replacementTemplate
        }

        init(groupIdLength: Int32) {
            let prefix = TSGroupThread.groupThreadUniqueIdPrefix
            let groupIdBase64StringLength = groupIdLength.base64Length

            let unredactedSize = 2
            let redactedSize = groupIdBase64StringLength - unredactedSize

            // This assertion exists to prevent someone from updating the values and forgetting to
            // update things here.
            owsAssert(
                prefix == "g" &&
                groupIdBase64StringLength >= (unredactedSize + 1) &&
                groupIdBase64StringLength <= 100
            )

            let base64Pattern = "A-Za-z0-9+/="
            let base64Char = "[\(base64Pattern)]"
            let notBase64Char = "[^\(base64Pattern)]"
            self.init(
                pattern: "(^|\(notBase64Char))\(prefix)\(base64Char){\(redactedSize)}(\(base64Char){\(unredactedSize)})($|\(notBase64Char))",
                replacementTemplate: "$1[ REDACTED_GROUP_ID:...$2 ]$3"
            )
        }
    }

    private let replacements: [Replacement] = [
        .init(
            pattern: "\\+\\d{7,12}(\\d{3})",
            replacementTemplate: "[ REDACTED_PHONE_NUMBER:xxx$1 ]"
        ),
        // It's important to redact GV2 IDs first because they're longer. If the shorter IDs were
        // first, we'd be left with a bunch of partially-redacted GV2 IDs.
        .init(groupIdLength: kGroupIdLengthV2),
        .init(groupIdLength: kGroupIdLengthV1),
        .init(
            pattern: "[\\da-f]{8}\\-[\\da-f]{4}\\-[\\da-f]{4}\\-[\\da-f]{4}\\-[\\da-f]{9}([\\da-f]{3})",
            options: .caseInsensitive,
            replacementTemplate: "[ REDACTED_UUID:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxx$1 ]"
        ),
        .init(
            pattern: "<([\\da-f]{2})[\\da-f]{0,6}( [\\da-f]{2,8})*>",
            options: .caseInsensitive,
            replacementTemplate: "[ REDACTED_DATA:$1... ]"
        ),
        // On iOS 13, when built with the 13 SDK, NSData's description has changed and needs to be
        // scrubbed specifically.
        // example log line: "Called someFunction with nsData: {length = 8, bytes = 0x0123456789abcdef}"
        //  scrubbed output: "Called someFunction with nsData: [ REDACTED_DATA:96 ]"
        .init(
            pattern: "\\{length = \\d+, bytes = 0x([\\da-f]{2})[\\.\\da-f ]*\\}",
            options: .caseInsensitive,
            replacementTemplate: "[ REDACTED_DATA:$1... ]"
        ),
        .init(
            pattern: "\\d+\\.\\d+\\.\\d+\\.(\\d+)",
            replacementTemplate: "[ REDACTED_IPV4_ADDRESS:...$1 ]"
        ),
        .init(
            pattern: "[\\da-f]{11,}([\\da-f]{3})",
            options: .caseInsensitive,
            replacementTemplate: "[ REDACTED_HEX:...$1 ]"
        ),
        // Redact base64 encoded UUIDs.
        // We take advantage of the known length of UUIDs (16 bytes, 128 bits),
        // which when encoded to base64 means 22 chars (6 bits per char, so 128/6 = 21.3)
        // plus we add padding ("=" is the reserved padding character) to make it 24.
        // Otherwise we'd just be matching arbitrary length text since all letters are covered.
        .init(
            pattern: (
                // Leading can be any non-matching character (so we
                // want leading whitespace or something else)
                // The exception is "/". The uuid might be in a url path,
                // and we want to redact it, so we need to allow leading
                // path delimiters.
                "([^\\da-zA-Z+])"
                // Capture the first 3 chars to retain after redaction
                + "([\\da-zA-Z/+]{3})"
                // Match the rest but throw it away
                + "[\\da-zA-Z/+]{19}"
                // Match the trailing padding
                + "\\=\\="
            ),
            replacementTemplate: "$1[ REDACTED_BASE64_UUID:$2... ]"
        )
    ]

    public override func format(message: DDLogMessage) -> String? {
        guard var logString = super.format(message: message) else {
            return nil
        }

        if logString.contains("/Attachments/") {
            return "[ REDACTED_CONTAINS_USER_PATH ]"
        }

        for replacement in replacements {
            logString = replacement.regex.stringByReplacingMatches(
                in: logString,
                range: logString.entireRange,
                withTemplate: replacement.replacementTemplate
            )
        }

        return logString
    }
}

private extension Int32 {
    var base64Length: Int { Int(4 * ceil(Double(self) / 3)) }
}
