//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Like MessageBody but with styles only, no mentions.
@objcMembers
public class StyleOnlyMessageBody: NSObject, Codable {
    public typealias Style = MessageBodyRanges.Style

    public let text: String
    public let styles: [NSRangedValue<Style>]

    public var isEmpty: Bool {
        return text.isEmpty
    }

    public var hasStyles: Bool {
        return styles.isEmpty.negated
    }

    public convenience init(messageBody: MessageBody) {
        self.init(text: messageBody.text, styles: messageBody.ranges.styles)
    }

    public convenience init(text: String, protos: [SSKProtoBodyRange]) {
        let bodyRanges = MessageBodyRanges(protos: protos)
        // Drop any mentions; don't even hydrate them.
        self.init(text: text, styles: bodyRanges.styles)
    }

    public convenience init(plaintext: String) {
        self.init(text: plaintext, styles: [])
    }

    public static var empty: StyleOnlyMessageBody { return StyleOnlyMessageBody(plaintext: "") }

    public init(text: String, styles: [NSRangedValue<Style>]) {
        self.text = text
        self.styles = styles
    }

    public func asMessageBody() -> MessageBody {
        return MessageBody(
            text: text,
            ranges: MessageBodyRanges(mentions: [:], styles: styles)
        )
    }

    // No mentions, so "hydration" is a no-op step.
    public func asHydratedMessageBody() -> HydratedMessageBody {
        return HydratedMessageBody(
            hydratedText: text,
            mentionAttributes: [],
            styleAttributes: styles.map {
                return .init(.fromOriginalRange($0.range, style: $0.value), range: $0.range)
            }
        )
    }

    public func asAttributedStringForDisplay(
        config: StyleDisplayConfiguration,
        baseAttributes: [NSAttributedString.Key: Any]? = nil,
        isDarkThemeEnabled: Bool
    ) -> NSAttributedString {
        let string = NSMutableAttributedString(string: text, attributes: baseAttributes ?? [:])
        return HydratedMessageBody.applyAttributes(
            on: string,
            mentionAttributes: [],
            styleAttributes: self.styles.map {
                return .init(.fromOriginalRange($0.range, style: $0.value), range: $0.range)
            },
            config: HydratedMessageBody.DisplayConfiguration(
                // Mentions are impossible on this class, so this is just a stub.
                mention: MentionDisplayConfiguration(
                    font: config.baseFont,
                    foregroundColor: config.textColor,
                    backgroundColor: nil
                ),
                style: config,
                searchRanges: nil
            ),
            isDarkThemeEnabled: isDarkThemeEnabled
        )
    }

    public func toProtoBodyRanges() -> [SSKProtoBodyRange] {
        // No need to validate length; all instances of this class are validated.
        return MessageBodyRanges(mentions: [:], styles: styles).toProtoBodyRanges()
    }

    public func stripAndDropFirst(_ count: Int) -> StyleOnlyMessageBody {
        stripAndPerformDrop(String.dropFirst, count)
    }

    public func stripAndDropLast(_ count: Int) -> StyleOnlyMessageBody {
        stripAndPerformDrop(String.dropLast, count)
    }

    private func stripAndPerformDrop(
        _ operation: (__owned String) -> (Int) -> Substring,
        _ count: Int
    ) -> StyleOnlyMessageBody {
        let originalStripped = text.stripped
        let finalText = String(operation(originalStripped)(count)).stripped
        let finalSubrange = (text as NSString).range(of: finalText)
        guard finalSubrange.location != NSNotFound, finalSubrange.length > 0 else {
            return .empty
        }
        let finalStyles: [NSRangedValue<Style>] = styles.compactMap { style in
            guard
                let intersection = style.range.intersection(finalSubrange),
                intersection.location != NSNotFound,
                intersection.length > 0
            else {
                return nil
            }
            return .init(
                style.value,
                range: NSRange(
                    location: intersection.location - finalSubrange.location,
                    length: intersection.length
                )
            )
        }
        return .init(text: finalText, styles: finalStyles)
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? StyleOnlyMessageBody else {
            return false
        }
        guard text == rhs.text else {
            return false
        }
        guard styles.count == rhs.styles.count else {
            return false
        }
        for i in 0..<styles.count {
            guard styles[i] == rhs.styles[i] else {
                return false
            }
        }
        return true
    }
}
