//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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

    static func youReceived(from fullName: String) -> String {
        let formatText = NSLocalizedString(
            "BADGE_GIFTING_YOU_RECEIVED_FORMAT",
            comment: "Shown when redeeming a gift you received to explain to the user that they've earned a badge. Embed {contact name}."
        )
        return String(format: formatText, fullName)
    }
}
