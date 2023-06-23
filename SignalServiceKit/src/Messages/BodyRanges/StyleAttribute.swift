//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// Note that this struct gets put into NSAttributedString,
// so we want it to mostly contain simple types and not
// hold references to other objects, as a string holding
// a reference to the outside world is very likely to cause
// surprises.
public struct StyleDisplayConfiguration: Equatable {
    public let baseFont: UIFont
    public let textColor: ThemedColor
    public let revealedSpoilerBgColor: ThemedColor?

    public let revealAllIds: Bool
    public let revealedIds: Set<StyleIdType>

    public init(
        baseFont: UIFont,
        textColor: ThemedColor,
        revealedSpoilerBgColor: ThemedColor? = nil,
        revealAllIds: Bool,
        revealedIds: Set<StyleIdType>
    ) {
        self.baseFont = baseFont
        self.textColor = textColor
        self.revealedSpoilerBgColor = revealedSpoilerBgColor
        self.revealAllIds = revealAllIds
        self.revealedIds = revealedIds
    }
}

internal struct StyleAttribute: Equatable, Hashable {
    typealias Style = MessageBodyRanges.Style
    typealias SingleStyle = MessageBodyRanges.SingleStyle
    typealias CollapsedStyle = MessageBodyRanges.CollapsedStyle

    /// Externally: identifies a single style range, even if the actual attribute has been
    /// split when applied, as happens when a parallel attribute is applied to the middle
    /// of a style range.
    ///
    /// Really this is just the original full range of the style, hashed. But that detail is
    /// irrelevant to everthing outside of this class.
    internal let ids: [SingleStyle: StyleIdType]
    internal let style: Style

    private static let key = NSAttributedString.Key("OWSStyle")
    private static let displayConfigKey = NSAttributedString.Key("OWSStyle.displayConfig")

    internal static func extractFromAttributes(
        _ attrs: [NSAttributedString.Key: Any]
    ) -> (StyleAttribute, StyleDisplayConfiguration?)? {
        guard let attribute = (attrs[Self.key] as? StyleAttribute) else {
            return nil
        }
        return (attribute, attrs[Self.displayConfigKey] as? StyleDisplayConfiguration)
    }

    internal static func fromCollapsedStyle(_ style: CollapsedStyle) -> Self {
        return .init(ids: style.originals.mapValues(\.id), style: style.style)
    }

    private init(ids: [SingleStyle: StyleIdType], style: Style) {
        self.ids = ids
        self.style = style
    }

    internal func applyAttributes(
        to string: NSMutableAttributedString,
        at range: NSRange,
        config: StyleDisplayConfiguration,
        searchRanges: HydratedMessageBody.DisplayConfiguration.SearchRanges?,
        isDarkThemeEnabled: Bool
    ) {
        var fontTraits: UIFontDescriptor.SymbolicTraits = []
        var attributes: [NSAttributedString.Key: Any] = [
            Self.key: self,
            Self.displayConfigKey: config
        ]
        if style.contains(.bold) {
            fontTraits.insert(.traitBold)
        }
        if style.contains(.italic) {
            fontTraits.insert(.traitItalic)
        }
        if style.contains(.monospace) {
            fontTraits.insert(.traitMonoSpace)
        }
        if style.contains(.strikethrough) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = config.textColor.color(isDarkThemeEnabled: isDarkThemeEnabled)
        }

        var isSpoilerRevealed = false
        if style.contains(.spoiler), let spoilerId = self.ids[.spoiler] {
            isSpoilerRevealed = config.revealAllIds || config.revealedIds.contains(spoilerId)
            if !isSpoilerRevealed {
                attributes[.foregroundColor] = UIColor.clear
                attributes[.backgroundColor] = config.textColor.color(isDarkThemeEnabled: isDarkThemeEnabled)
            } else if let revealedSpoilerBgColor = config.revealedSpoilerBgColor {
                attributes[.foregroundColor] = config.textColor.color(isDarkThemeEnabled: isDarkThemeEnabled)
                attributes[.backgroundColor] = revealedSpoilerBgColor.color(isDarkThemeEnabled: isDarkThemeEnabled)
            }
        }
        if !fontTraits.isEmpty {
            attributes[.font] = config.baseFont.withTraits(fontTraits)
        }
        string.addAttributes(attributes, range: range)

        // if we had a spoiler range, apply and search ranges to override
        // spoiler attributes we applied above.
        if style.contains(.spoiler), !isSpoilerRevealed, let searchRanges {
            for searchMatchRange in searchRanges.matchedRanges {
                guard
                    let intersection = searchMatchRange.intersection(range),
                    intersection.length > 0,
                    intersection.location != NSNotFound
                else {
                    continue
                }
                string.addAttributes(
                    [
                        .backgroundColor: searchRanges.matchingBackgroundColor.color(isDarkThemeEnabled: isDarkThemeEnabled),
                        .foregroundColor: UIColor.clear,
                        Self.key: self
                    ],
                    range: intersection
                )
            }
        }
    }

    private static let plaintextSpoilerCharacter = "■"
    private static let maxPlaintextSpoilerLength = 4

    internal func applyPlaintextSpoiler(
        to string: NSMutableString,
        at range: NSRange
    ) {
        string.replaceCharacters(
            in: range,
            with: String(
                repeating: Self.plaintextSpoilerCharacter,
                count: min(range.length, Self.maxPlaintextSpoilerLength)
            )
        )
    }
}

extension UIFont {

    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {

        // create a new font descriptor with the given traits
        guard let fd = fontDescriptor.withSymbolicTraits(traits) else {
            // the given traits couldn't be applied, return self
            return self
        }

        // return a new font with the created font descriptor
        return UIFont(descriptor: fd, size: pointSize)
    }
}
