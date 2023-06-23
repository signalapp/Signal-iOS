//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class RecoveredHydratedMessageBody {

    private let string: NSAttributedString
    private let mentionAttributes: [NSRangedValue<MentionAttribute>]
    private let styleAttributes: [NSRangedValue<StyleAttribute>]
    private var mentionConfig: MentionDisplayConfiguration?
    private var styleConfig: StyleDisplayConfiguration?
    private var searchRangesConfig: HydratedMessageBody.DisplayConfiguration.SearchRanges?

    private init(
        string: NSAttributedString,
        mentionAttributes: [NSRangedValue<MentionAttribute>],
        styleAttributes: [NSRangedValue<StyleAttribute>],
        mentionConfig: MentionDisplayConfiguration?,
        styleConfig: StyleDisplayConfiguration?,
        searchRangesConfig: HydratedMessageBody.DisplayConfiguration.SearchRanges?
    ) {
        self.string = string
        self.mentionAttributes = mentionAttributes
        self.styleAttributes = styleAttributes
        self.mentionConfig = mentionConfig
        self.styleConfig = styleConfig
        self.searchRangesConfig = searchRangesConfig
    }

    public static func recover(
        from string: NSAttributedString
    ) -> RecoveredHydratedMessageBody {
        var mentionAttributes = [NSRangedValue<MentionAttribute>]()
        var mentionConfig: MentionDisplayConfiguration?
        var styleAttributes = [NSRangedValue<StyleAttribute>]()
        var styleConfig: StyleDisplayConfiguration?
        var searchRangeConfig: HydratedMessageBody.DisplayConfiguration.SearchRanges?
        string.enumerateAttributes(
            in: string.entireRange,
            using: { attrs, range, _ in
                // Mentions and styles constructed this way can overlap, but never partially.
                // either a range has a mention on its entire range, a style on its entire range,
                // both, or none. There is no such thing as a range with a partial style/mention subrange.
                // This fact is relied upon in `tappableItems`.
                if let (mention, config) = MentionAttribute.extractFromAttributes(attrs) {
                    mentionAttributes.append(.init(mention, range: range))
                    owsAssertDebug(mentionConfig == nil || mentionConfig == config, "Should not have multiple configs on one string")
                    mentionConfig = config
                }
                if let (style, config) = StyleAttribute.extractFromAttributes(attrs) {
                    styleAttributes.append(.init(style, range: range))
                    owsAssertDebug(styleConfig == nil || styleConfig == config, "Should not have multiple configs on one string")
                    styleConfig = config
                }
                if let config = HydratedMessageBody.extractSearchRangeConfigFromAttributes(attrs) {
                    owsAssertDebug(
                        searchRangeConfig == nil || searchRangeConfig == config,
                        "Should not have multiple configs on one string"
                    )
                    searchRangeConfig = config
                }
            }
        )
        return .init(
            string: string,
            mentionAttributes: mentionAttributes,
            styleAttributes: styleAttributes,
            mentionConfig: mentionConfig,
            styleConfig: styleConfig,
            searchRangesConfig: searchRangeConfig
        )
    }

    public enum Applyable {
        /// The string has previously had attributes applied with a recoverable configuration that can
        /// be reapplied (with a potentially updated theme)
        case alreadyConfigured(apply: (_ isDarkThemeEnabled: Bool) -> NSMutableAttributedString)
        /// The string has necer had attributes applied; configuration is mandatory to apply.
        case unconfigured(apply: (_ config: HydratedMessageBody.DisplayConfiguration, _ isDarkThemeEnabled: Bool) -> NSMutableAttributedString)
    }

    /// If you want to reapply without having a config available you must go through this method
    /// to safely unwrap values. It may be that the .notConfigured case doesn't need handling, e.g.
    /// when updating the global app theme for a as-yet-unapplied string, but the explicit callout
    /// ensures this doesn't happen unexpectedly.
    public func applyable() -> Applyable {
        let config: HydratedMessageBody.DisplayConfiguration?
        if let mentionConfig, let styleConfig {
            config = .init(mention: mentionConfig, style: styleConfig, searchRanges: searchRangesConfig)
        } else if let mentionConfig, styleAttributes.isEmpty {
            // If we don't have any style attributes, we don't actually require a style config.
            // make a "fake" one and keep going.
            config = .init(
                mention: mentionConfig,
                style: .init(
                    baseFont: .systemFont(ofSize: 12),
                    textColor: ThemedColor(light: .black, dark: .black),
                    revealAllIds: false,
                    revealedIds: Set()
                ),
                searchRanges: searchRangesConfig
            )
        } else if let styleConfig, mentionAttributes.isEmpty {
            // If we don't have any mention attributes, we don't actually require a mention config.
            // make a "fake" one and keep going.
            config = .init(
                mention: .init(
                    font: .systemFont(ofSize: 12),
                    foregroundColor: ThemedColor(light: .black, dark: .black),
                    backgroundColor: nil
                ),
                style: styleConfig,
                searchRanges: searchRangesConfig
            )
        } else {
            config = nil
        }

        if let config {
            return .alreadyConfigured(apply: { isDarkThemeEnabled in
                self.reapplyAttributes(
                    config: config,
                    isDarkThemeEnabled: isDarkThemeEnabled
                )
            })
        } else {
            return .unconfigured(apply: { config, isDarkThemeEnabled in
                self.reapplyAttributes(config: config, isDarkThemeEnabled: isDarkThemeEnabled)
            })
        }
    }

    public func reapplyAttributes(
        config: HydratedMessageBody.DisplayConfiguration,
        isDarkThemeEnabled: Bool
    ) -> NSMutableAttributedString {
        // Remember the config so we can reapply later if we need to.
        self.mentionConfig = config.mention
        self.styleConfig = config.style
        self.searchRangesConfig = config.searchRanges

        let mutableString: NSMutableAttributedString = {
            if let mutableString = self.string as? NSMutableAttributedString {
                return mutableString
            }
            return NSMutableAttributedString(attributedString: self.string)
        }()
        return HydratedMessageBody.applyAttributes(
            on: mutableString,
            mentionAttributes: mentionAttributes,
            styleAttributes: styleAttributes,
            config: config,
            isDarkThemeEnabled: isDarkThemeEnabled
        )
    }

    public func tappableItems(
        revealedSpoilerIds: Set<Int>,
        dataDetector: NSDataDetector?
    ) -> [HydratedMessageBody.TappableItem] {
        return HydratedMessageBody.tappableItems(
            text: string.string,
            mentionAttributes: mentionAttributes,
            styleAttributes: styleAttributes,
            revealedSpoilerIds: revealedSpoilerIds,
            dataDetector: dataDetector
        )
    }

    /// Ordered by location from start of the string, non overlapping.
    public func mentions() -> [(NSRange, UUID)] {
        return mentionAttributes.map { ($0.range, $0.value.mentionUuid) }
    }

    // Ideally we should be explicitly holding onto a MessageBody, not recovering from
    // an attributed string. Needed for now because message bubbles hold only the
    // attributed string.
    public func toMessageBody() -> MessageBody {
        var mentions = [NSRange: UUID]()
        mentionAttributes.forEach {
            mentions[$0.range] = $0.value.mentionUuid
        }
        return MessageBody(
            text: string.string,
            ranges: MessageBodyRanges(
                mentions: mentions,
                styles: HydratedMessageBody.flattenStylesPreservingSharedIds(styleAttributes)
            )
        )
    }
}
