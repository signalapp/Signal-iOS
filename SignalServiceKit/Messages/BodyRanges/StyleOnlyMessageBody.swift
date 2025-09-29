//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Like MessageBody but with styles only, no mentions.
final public class StyleOnlyMessageBody: Codable, Equatable {
    public typealias Style = MessageBodyRanges.Style
    public typealias CollapsedStyle = MessageBodyRanges.CollapsedStyle

    public let text: String
    public let collapsedStyles: [NSRangedValue<CollapsedStyle>]

    public var isEmpty: Bool {
        return text.isEmpty
    }

    public var length: Int { (text as NSString).length }

    public var hasStyles: Bool {
        return collapsedStyles.isEmpty.negated
    }

    public convenience init(messageBody: MessageBody) {
        self.init(text: messageBody.text, collapsedStyles: messageBody.ranges.collapsedStyles)
    }

    public convenience init(text: String, protos: [SSKProtoBodyRange]) {
        let bodyRanges = MessageBodyRanges(protos: protos)
        // Drop any mentions; don't even hydrate them.
        self.init(text: text, collapsedStyles: bodyRanges.collapsedStyles)
    }

    public convenience init(text: String, style: MessageBodyRanges.SingleStyle) {
        self.init(text: text, styles: style.asStyle)
    }

    public convenience init(text: String, styles: MessageBodyRanges.Style) {
        let protos = styles.contents.map { style in
            let protoBuilder = SSKProtoBodyRange.builder()
            protoBuilder.setStart(0)
            protoBuilder.setLength(UInt32((text as NSString).length))
            protoBuilder.setStyle(style.asProtoStyle)
            return protoBuilder.buildInfallibly()
        }
        self.init(text: text, protos: protos)
    }

    public convenience init(plaintext: String) {
        self.init(text: plaintext, collapsedStyles: [])
    }

    public static var empty: StyleOnlyMessageBody { return StyleOnlyMessageBody(plaintext: "") }

    public init(text: String, collapsedStyles: [NSRangedValue<CollapsedStyle>]) {
        self.text = text
        let textRange = NSRange(location: 0, length: (text as NSString).length)
        self.collapsedStyles = collapsedStyles.compactMap {
            guard let intersection = $0.range.intersection(textRange), intersection.length > 0 else {
                return nil
            }
            return .init($0.value, range: intersection)
        }
    }

    public func asMessageBody() -> MessageBody {
        return MessageBody(
            text: text,
            ranges: MessageBodyRanges(
                mentions: [:],
                orderedMentions: [],
                collapsedStyles: collapsedStyles
            )
        )
    }

    // No mentions, so "hydration" is a no-op step.
    public func asHydratedMessageBody() -> HydratedMessageBody {
        return HydratedMessageBody(
            hydratedText: text,
            mentionAttributes: [],
            styleAttributes: collapsedStyles.map {
                return .init(.fromCollapsedStyle($0.value), range: $0.range)
            }
        )
    }

    public func asAttributedStringForDisplay(
        config: StyleDisplayConfiguration,
        baseFont: UIFont? = nil,
        baseTextColor: UIColor? = nil,
        textAlignment: NSTextAlignment? = nil,
        isDarkThemeEnabled: Bool
    ) -> NSAttributedString {
        let baseFont = baseFont ?? config.baseFont
        let baseTextColor = baseTextColor ?? config.textColor.color(isDarkThemeEnabled: isDarkThemeEnabled)

        var baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: baseTextColor
        ]
        if let textAlignment {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = textAlignment
            baseAttributes[.paragraphStyle] = paragraphStyle
        }
        let string = NSMutableAttributedString(
            string: text,
            attributes: baseAttributes
        )
        return HydratedMessageBody.applyAttributes(
            on: string,
            mentionAttributes: [],
            styleAttributes: self.collapsedStyles.map {
                return .init(.fromCollapsedStyle($0.value), range: $0.range)
            },
            config: HydratedMessageBody.DisplayConfiguration(
                baseFont: config.baseFont,
                baseTextColor: config.textColor,
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
        return MessageBodyRanges(
            mentions: [:],
            orderedMentions: [],
            collapsedStyles: collapsedStyles
        ).toProtoBodyRanges()
    }

    public func stripAndDropFirst(_ count: Int) -> StyleOnlyMessageBody {
        stripAndPerformDrop(String.dropFirst, count)
    }

    public func stripAndDropLast(_ count: Int) -> StyleOnlyMessageBody {
        stripAndPerformDrop(String.dropLast, count)
    }

    public func addingSuffix(_ suffix: StyleOnlyMessageBody) -> StyleOnlyMessageBody {
        let suffixOffset = self.length
        return .init(text: self.text + suffix.text, collapsedStyles: collapsedStyles + suffix.collapsedStyles.map {
            return NSRangedValue($0.value, range: NSRange(location: $0.range.location + suffixOffset, length: $0.range.length))
        })
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
        let finalStyles: [NSRangedValue<CollapsedStyle>] = collapsedStyles.compactMap { style in
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
        return .init(text: finalText, collapsedStyles: finalStyles)
    }

    public static func == (lhs: StyleOnlyMessageBody, rhs: StyleOnlyMessageBody) -> Bool {
        guard lhs.text == rhs.text else {
            return false
        }
        guard lhs.collapsedStyles.count == rhs.collapsedStyles.count else {
            return false
        }
        for i in 0..<lhs.collapsedStyles.count {
            guard lhs.collapsedStyles[i] == rhs.collapsedStyles[i] else {
                return false
            }
        }
        return true
    }

    // MARK: - Codable

    public enum CodingKeys: String, CodingKey {
        case text
        case collapsedStyles = "styles"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.text = try container.decode(String.self, forKey: .text)

        // Backwards compability; this used to contain NSRangedValue<Style>,
        // but now contains NSRangedValue<CollapsedStyle>
        if let rawStyles = try? container.decodeIfPresent([NSRangedValue<Style>].self, forKey: .collapsedStyles) {
            // Re-process the styles in order to collapse them.
            let singleStyles = rawStyles.flatMap { style in
                return style.value.contents.map {
                    return NSRangedValue($0, range: style.range)
                }
            }
            let messageBodyRanges = MessageBodyRanges(mentions: [:], styles: singleStyles)
            self.collapsedStyles = messageBodyRanges.collapsedStyles
        } else {
            self.collapsedStyles = try container.decode([NSRangedValue<CollapsedStyle>].self, forKey: .collapsedStyles)
        }
    }
}
