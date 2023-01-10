//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

struct BadgeGiftingStrings {
    private init() {}

    static var giftBadgeTitle: String {
        NSLocalizedString(
            "BADGE_GIFTING_CHAT_TITLE",
            comment: "Shown on a gift badge message and when tapping a redeemed gift message to denote the presence of a gift badge."
        )
    }

    static func youReceived(from shortName: String) -> String {
        let formatText = NSLocalizedString(
            "DONATION_ON_BEHALF_OF_A_FRIEND_YOU_RECEIVED_A_BADGE_FORMAT",
            comment: "A friend has donated on your behalf and you received a badge. This text says that you received a badge, and from whom. Embeds {{contact's short name, such as a first name}}."
        )
        return String(format: formatText, shortName)
    }
}
