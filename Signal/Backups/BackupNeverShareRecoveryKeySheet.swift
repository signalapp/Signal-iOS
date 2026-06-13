//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class BackupNeverShareRecoveryKeySheet: HeroSheetViewController {
    init(
        primaryButton: HeroSheetViewController.Button,
        secondaryButton: HeroSheetViewController.Button?,
    ) {
        let bodyText: NSAttributedString = NSAttributedString.composed(of: [
            OWSLocalizedString(
                "BACKUP_NEVER_SHARE_RECOVERY_KEY_SHEET_BODY",
                comment: "Body for a warning sheet shown to discourage the user from sharing their 'Recovery Key', warning them not to share it with anyone.",
            ),
            " ",
            "<link>\(CommonStrings.learnMore)</link>",
        ]).styled(
            with: .font(.dynamicTypeSubheadline),
            .xmlRules([
                .style("bold", StringStyle(.font(.dynamicTypeSubheadline.bold()))),
                .style("link", StringStyle(.link(.Support.phishingPrevention))),
            ]),
        )

        super.init(
            hero: .circleIcon(
                icon: .errorTriangle,
                iconSize: 40,
                tintColor: .Signal.red,
                backgroundColor: UIColor(rgbHex: 0xF8E0D9),
            ),
            title: OWSLocalizedString(
                "BACKUP_NEVER_SHARE_RECOVERY_KEY_SHEET_TITLE",
                comment: "Title for a warning sheet shown to discourage the user from sharing their 'Recovery Key'.",
            ),
            body: HeroSheetViewController.Body(
                textContent: .attributed(bodyText),
            ),
            primary: .button(primaryButton),
            secondary: secondaryButton.map { .button($0) },
        )
    }
}
