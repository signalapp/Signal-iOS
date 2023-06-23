//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

extension StyleDisplayConfiguration {

    public static func forMessageBubble(
        isIncoming: Bool,
        revealedSpoilerIds: Set<StyleIdType>
    ) -> Self {
        let textColor = isIncoming
            ? ConversationStyle.bubbleTextColorIncomingThemed
            : ConversationStyle.bubbleTextColorOutgoingThemed
        return StyleDisplayConfiguration(
            baseFont: .dynamicTypeBody,
            textColor: textColor,
            revealAllIds: false,
            revealedIds: revealedSpoilerIds
        )
    }

    public static func quotedReply(revealedSpoilerIds: Set<StyleIdType>) -> Self {
        return StyleDisplayConfiguration(
            baseFont: .dynamicTypeBody,
            textColor: primaryTextColor,
            revealAllIds: false,
            revealedIds: revealedSpoilerIds
        )
    }

    public static var groupReply: Self {
        return StyleDisplayConfiguration(
            baseFont: .dynamicTypeBody,
            textColor: .fixed(.ows_gray05),
            revealAllIds: false,
            revealedIds: Set()
        )
    }

    public static func forConversationListSnippet(
        baseFont: UIFont,
        textColor: ThemedColor
    ) -> StyleDisplayConfiguration {
        return StyleDisplayConfiguration(
            baseFont: baseFont,
            textColor: textColor,
            revealAllIds: false,
            revealedIds: Set()
        )
    }

    public static var conversationListSearchResultSnippet: StyleDisplayConfiguration {
        return StyleDisplayConfiguration(
            baseFont: UIFont.dynamicTypeBody2,
            textColor: ThemedColor(light: Theme.lightThemeSecondaryTextAndIconColor, dark: Theme.darkThemeSecondaryTextAndIconColor),
            revealAllIds: false,
            revealedIds: Set()
        )
    }

    public static func longTextView(revealedSpoilerIds: Set<StyleIdType>) -> StyleDisplayConfiguration {
        return StyleDisplayConfiguration(
            baseFont: .dynamicTypeBody,
            textColor: primaryTextColor,
            revealAllIds: false,
            revealedIds: revealedSpoilerIds
        )
    }

    public static func mediaCaption(revealedSpoilerIds: Set<StyleIdType>) -> StyleDisplayConfiguration {
        return StyleDisplayConfiguration(
            baseFont: .dynamicTypeBodyClamped,
            textColor: .fixed(.white),
            revealAllIds: false,
            revealedIds: revealedSpoilerIds
        )
    }

    private static let primaryTextColor = ThemedColor(
        light: Theme.lightThemePrimaryColor,
        dark: Theme.darkThemePrimaryColor
    )

    public static var composing: Self {
        return StyleDisplayConfiguration(
            baseFont: .dynamicTypeBody,
            textColor: ConversationStyle.bubbleTextColorIncomingThemed,
            revealedSpoilerBgColor: ThemedColor(light: .ows_gray20, dark: .ows_gray60),
            revealAllIds: true,
            revealedIds: Set()
        )
    }

    public static var composingAttachment: Self {
        return StyleDisplayConfiguration(
            baseFont: .dynamicTypeBody,
            textColor: .fixed(Theme.darkThemePrimaryColor),
            revealedSpoilerBgColor: .fixed(.ows_gray75),
            revealAllIds: true,
            revealedIds: Set()
        )
    }

    public static var composingGroupReply: Self {
        return StyleDisplayConfiguration(
            baseFont: .dynamicTypeBody,
            textColor: .fixed(.ows_gray05),
            revealedSpoilerBgColor: .fixed(.ows_gray60),
            revealAllIds: true,
            revealedIds: Set()
        )
    }
}
