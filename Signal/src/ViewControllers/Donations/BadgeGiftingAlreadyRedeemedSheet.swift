//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class BadgeGiftingAlreadyRedeemedSheet: HeroSheetViewController {
    init(badge: ProfileBadge, shortName: String) {
        let titleFormat = OWSLocalizedString(
            "DONATION_ON_BEHALF_OF_A_FRIEND_REDEEM_BADGE_TITLE_FORMAT",
            comment: "A friend has donated on your behalf and you received a badge. A sheet opens for you to redeem this badge. Embeds {{contact's short name, such as a first name}}.",
        )
        let bodyFormat = OWSLocalizedString(
            "DONATION_ON_BEHALF_OF_A_FRIEND_YOU_RECEIVED_A_BADGE_FORMAT",
            comment: "A friend has donated on your behalf and you received a badge. This text says that you received a badge, and from whom. Embeds {{contact's short name, such as a first name}}.",
        )
        super.init(
            hero: .image(badge.assets.universal160 ?? UIImage(), height: 160),
            title: String.nonPluralLocalizedStringWithFormat(titleFormat, shortName),
            body: String.nonPluralLocalizedStringWithFormat(bodyFormat, shortName),
            primaryButton: nil,
        )
    }
}
