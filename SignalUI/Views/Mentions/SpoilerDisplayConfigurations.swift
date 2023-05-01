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

    public static var quotedReply: Self {
        return StyleDisplayConfiguration(
            baseFont: .dynamicTypeBody,
            textColor: primaryTextColor,
            revealAllIds: false,
            // No reveals in quoted replies under any circumstances.
            revealedIds: Set()
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
