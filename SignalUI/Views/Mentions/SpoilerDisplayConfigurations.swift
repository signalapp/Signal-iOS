//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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

    // TODO: this a placeholder for some callsites
    public static func todo() -> Self {
        return StyleDisplayConfiguration(
            baseFont: .dynamicTypeBody,
            textColor: .fixed(.black),
            revealAllIds: true,
            revealedIds: Set()
        )
    }
}
