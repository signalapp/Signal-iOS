//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CocoaLumberjack
import Foundation

public class ScrubbingLogFormatter: NSObject, DDLogFormatter {
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

        static func base64(prefix: String, length: Int) -> Replacement {
            let base64Length = ((length + 2) / 3) * 4
            let base64Padding = Data.base64PaddingCount(for: length)

            // It's important to have some padding because we use that to mark the end
            // of the groupId. If we don't have padding, then we need to sort the
            // groupId Replacements from longest to shortest.
            owsPrecondition(base64Padding != 0)

            let unredactedLength = 3
            let redactedLength = base64Length - base64Padding - unredactedLength

            owsPrecondition(redactedLength >= 1)

            // We want to find a non-matching character before the match starts. But
            // "/" is excluded so that we can find matches within URL paths.
            let base64Leading = "A-Za-z0-9+"
            let base64Character = "A-Za-z0-9+/"
            let paddingCharacter = "="

            return Replacement(
                pattern: "(^|[^\(base64Leading)])\(prefix)[\(base64Character)]{\(redactedLength)}([\(base64Character)]{\(unredactedLength)}\(paddingCharacter){\(base64Padding)})",
                replacementTemplate: "$1\(prefix)…$2"
            )
        }

        static let callLink: Replacement = Replacement(
            pattern: #"([bcdfghkmnpqrstxz]{4})(-[bcdfghkmnpqrstxz]{4}){7}"#,
            replacementTemplate: "$1-…-xxxx"
        )

        static let phoneNumber: Replacement = Replacement(
            pattern: #"\+\d{7,12}(\d{3})"#,
            replacementTemplate: "+x…$1"
        )

        static let uuid: Replacement = Replacement(
            pattern: #"[\da-f]{8}\-[\da-f]{4}\-[\da-f]{4}\-[\da-f]{4}\-[\da-f]{9}([\da-f]{3})"#,
            options: .caseInsensitive,
            replacementTemplate: "xxxx-xx-xx-xxx$1"
        )

        static let data: Replacement = Replacement(
            pattern: #"<([\da-f]{2})[\da-f]{0,6}( [\da-f]{2,8})*>"#,
            options: .caseInsensitive,
            replacementTemplate: "<$1…>"
        )

        /// On iOS 13, when built with the 13 SDK, NSData's description has changed and needs to be
        /// scrubbed specifically.
        /// example log line: "Called someFunction with nsData: {length = 8, bytes = 0x0123456789abcdef}"
        ///  scrubbed output: "Called someFunction with nsData: [ REDACTED_DATA:96 ]"
        static let iOS13Data: Replacement = Replacement(
            pattern: #"\{length = \d+, bytes = 0x([\da-f]{2})[\.\da-f ]*\}"#,
            options: .caseInsensitive,
            replacementTemplate: "<$1…>"
        )

        /// IPv6 addresses are _hard_.
        ///
        /// This regex was borrowed from RingRTC:
        /// https://github.com/signalapp/ringrtc/blob/1ae8110dfe2693f6e3c05d4d9deb449b9df73d79/src/rust/src/core/util.rs#L184-L198
        static let ipv6Address: Replacement = Replacement(
            pattern: (
               "[Ff][Ee]80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|"
               + "(::)?([0-9a-fA-F]{1,4}:){1,4}:([0-9]{1,3}\\.){3,3}[0-9]{1,3}|"
               + "([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|"
               + "([0-9a-fA-F]{1,4}:){1,1}(:[0-9a-fA-F]{1,4}){1,6}|"
               + "([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|"
               + "([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|"
               + "([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|"
               + "([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|"
               + "([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|"
               + "([0-9a-fA-F]{1,4}:){1,7}:|"
               + "::([fF]{4}(:0{1,4}){0,1}:){0,1}([0-9]{1,3}\\.){3,3}[0-9]{1,3}|"
               + ":((:[0-9a-fA-F]{1,4}){1,7}|:)"
            ),
            replacementTemplate: "[IPV6]"
        )

        static let ipv4Address: Replacement = Replacement(
            pattern: "\\d+\\.\\d+\\.\\d+\\.(\\d+)",
            replacementTemplate: "x.x.x.$1"
        )

        static let hex: Replacement = Replacement(
            pattern: "[\\da-f]{11,}([\\da-f]{3})",
            options: .caseInsensitive,
            replacementTemplate: "…$1"
        )
    }

    private let replacements: [Replacement] = [
        .phoneNumber,
        .base64(prefix: TSGroupThread.groupThreadUniqueIdPrefix, length: Int(kGroupIdLengthV2)),
        .base64(prefix: TSGroupThread.groupThreadUniqueIdPrefix, length: Int(kGroupIdLengthV1)),
        .callLink,
        .uuid,
        .data,
        .iOS13Data,
        // Important to redact IPv6 before IPv4, since the former can contain
        // the latter.
        .ipv6Address,
        .ipv4Address,
        .hex,
        .base64(prefix: "", length: 32),
        .base64(prefix: "", length: 16),
    ]

    public func format(message logMessage: DDLogMessage) -> String? {
        return LogFormatter.formatLogMessage(logMessage, modifiedMessage: redactMessage(logMessage.message))
    }

    public func redactMessage(_ logString: String) -> String {
        var logString = logString

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
