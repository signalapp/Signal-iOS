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
    public let spoilerAnimationColorOverride: ThemedColor?
    public let revealedSpoilerBgColor: ThemedColor?

    public let revealAllIds: Bool
    public let revealedIds: Set<StyleIdType>

    /// If true, unrevealed spoiler text will be invisible (clear).
    /// If false, unrevealed spoiler text will use `textColor` as its background color.
    public let useAnimatedSpoilers: Bool

    public var spoilerColor: ThemedColor {
        if FeatureFlags.spoilerAnimations, let spoilerAnimationColorOverride {
            return spoilerAnimationColorOverride
        } else {
            return textColor
        }
    }

    public init(
        baseFont: UIFont,
        textColor: ThemedColor,
        spoilerAnimationColorOverride: ThemedColor? = nil,
        revealedSpoilerBgColor: ThemedColor? = nil,
        revealAllIds: Bool,
        revealedIds: Set<StyleIdType>,
        useAnimatedSpoilers: Bool
    ) {
        self.baseFont = baseFont
        self.textColor = textColor
        self.spoilerAnimationColorOverride = spoilerAnimationColorOverride
        self.revealedSpoilerBgColor = revealedSpoilerBgColor
        self.revealAllIds = revealAllIds
        self.revealedIds = revealedIds
        self.useAnimatedSpoilers = useAnimatedSpoilers
    }

    public func hashForSpoilerFrames(into hasher: inout Hasher) {
        hasher.combine(textColor)
        hasher.combine(spoilerAnimationColorOverride)
        hasher.combine(revealAllIds)
        hasher.combine(revealedIds)
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
        var attributes: [NSAttributedString.Key: Any] = [:]
        if style.contains(.bold) {
            fontTraits.insert(.traitBold)
        }
        if style.contains(.italic) {
            fontTraits.insert(.traitItalic)
        }
        if style.contains(.monospace) {
            fontTraits.insert(.traitMonoSpace)
        }

        var isSpoilerRevealed: Bool?
        if style.contains(.spoiler), let spoilerId = self.ids[.spoiler] {
            isSpoilerRevealed = config.revealAllIds || config.revealedIds.contains(spoilerId)
            if !isSpoilerRevealed! {
                attributes[.foregroundColor] = UIColor.clear
                if config.useAnimatedSpoilers {
                    attributes[.backgroundColor] = UIColor.clear
                } else {
                    attributes[.backgroundColor] = config.spoilerColor.color(isDarkThemeEnabled: isDarkThemeEnabled)
                }
            } else if let revealedSpoilerBgColor = config.revealedSpoilerBgColor {
                attributes[.foregroundColor] = config.textColor.color(isDarkThemeEnabled: isDarkThemeEnabled)
                attributes[.backgroundColor] = revealedSpoilerBgColor.color(isDarkThemeEnabled: isDarkThemeEnabled)
            }
        }

        if style.contains(.strikethrough) && (isSpoilerRevealed ?? true) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = config.textColor.color(isDarkThemeEnabled: isDarkThemeEnabled)
        }

        if !fontTraits.isEmpty {
            attributes[.font] = config.baseFont.withTraits(fontTraits)
        }
        string.addAttributes(attributes, range: range)

        // if we had a spoiler range, apply and search ranges to override
        // spoiler attributes we applied above.
        if style.contains(.spoiler), !(isSpoilerRevealed ?? false), let searchRanges {
            for searchMatchRange in searchRanges.matchedRanges {
                guard
                    let intersection = searchMatchRange.intersection(range),
                    intersection.length > 0,
                    intersection.location != NSNotFound
                else {
                    continue
                }
                let backgroundColor: UIColor
                if config.useAnimatedSpoilers {
                    backgroundColor = .clear
                } else {
                    backgroundColor = searchRanges.matchingBackgroundColor.color(isDarkThemeEnabled: isDarkThemeEnabled)
                }
                string.addAttributes(
                    [
                        .backgroundColor: backgroundColor,
                        .foregroundColor: UIColor.clear
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
