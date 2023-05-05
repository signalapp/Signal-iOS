//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension MentionDisplayConfiguration {

    public static var incomingMessageBubble: Self {
        return config(
            foregroundColor: ConversationStyle.bubbleTextColorIncomingThemed,
            backgroundColor: ThemedColor(light: .ows_gray20, dark: .ows_gray60)
        )
    }

    public static var outgoingMessageBubble: Self {
        return config(
            foregroundColor: ConversationStyle.bubbleTextColorOutgoingThemed,
            backgroundColor: .fixed(UIColor(white: 0, alpha: 0.25))
        )
    }

    public static var composingAttachment: Self {
        return config(
            foregroundColor: .fixed(Theme.darkThemePrimaryColor),
            backgroundColor: .fixed(.ows_gray75)
        )
    }

    public static var quotedReply: Self {
        return config(
            foregroundColor: primaryTextColor,
            backgroundColor: nil
        )
    }

    public static var longMessageView: Self {
        return config(
            foregroundColor: primaryTextColor,
            backgroundColor: ThemedColor(
                light: .ows_blackAlpha20,
                dark: .ows_signalBlueDark
            )
        )
    }

    public static var groupReply: Self {
        return config(
            foregroundColor: .fixed(.ows_gray05),
            backgroundColor: .fixed(.ows_gray60)
        )
    }

    public static func conversationListSnippet(
        font: UIFont,
        textColor: ThemedColor
    ) -> Self {
        return MentionDisplayConfiguration(
            font: font,
            foregroundColor: textColor,
            backgroundColor: nil
        )
    }

    public static var conversationListSearchResultSnippet: MentionDisplayConfiguration {
        return MentionDisplayConfiguration(
            font: .dynamicTypeBody2,
            foregroundColor: ThemedColor(light: Theme.lightThemeSecondaryTextAndIconColor, dark: Theme.darkThemeSecondaryTextAndIconColor),
            backgroundColor: nil
        )
    }

    public static var composing: Self { .incomingMessageBubble }

    public static var mediaCaption: MentionDisplayConfiguration {
        return MentionDisplayConfiguration(
            font: .dynamicTypeBodyClamped,
            foregroundColor: .fixed(.white),
            backgroundColor: nil
        )
    }

    private static let primaryTextColor = ThemedColor(
        light: Theme.lightThemePrimaryColor,
        dark: Theme.darkThemePrimaryColor
    )

    private static func config(
        foregroundColor: ThemedColor,
        backgroundColor: ThemedColor?
    ) -> Self {
        return MentionDisplayConfiguration(
            font: .dynamicTypeBody,
            foregroundColor: foregroundColor,
            backgroundColor: backgroundColor
        )
    }
}
