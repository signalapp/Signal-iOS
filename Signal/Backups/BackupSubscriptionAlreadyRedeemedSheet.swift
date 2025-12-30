//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class BackupSubscriptionAlreadyRedeemedSheet: HeroSheetViewController {
    init() {
        super.init(
            hero: .circleIcon(
                icon: .backupErrorBold,
                iconSize: 40,
                tintColor: .orange,
                backgroundColor: UIColor(rgbHex: 0xF9E4B6),
            ),
            title: OWSLocalizedString(
                "BACKUP_SETTINGS_SUBSCRIPTION_ALREADY_REDEEMED_SHEET_TITLE",
                comment: "Title for a sheet explaining that the user's Backups subscription was already redeemed.",
            ),
            body: OWSLocalizedString(
                "BACKUP_SETTINGS_SUBSCRIPTION_ALREADY_REDEEMED_SHEET_BODY",
                comment: "Body for a sheet explaining that the user's Backups subscription was already redeemed.",
            ),
            primaryButton: .dismissing(
                title: OWSLocalizedString(
                    "BACKUP_SETTINGS_SUBSCRIPTION_ALREADY_REDEEMED_SHEET_GOT_IT_BUTTON",
                    comment: "Button for a sheet explaining that the user's Backups subscription was already redeemed.",
                ),
            ),
            secondaryButton: Button(
                title: CommonStrings.contactSupport,
                style: .secondary,
                action: .custom({ sheet in
                    sheet.dismiss(animated: true) {
                        guard let frontmostViewController = CurrentAppContext().frontmostViewController() else {
                            owsFailDebug("Missing frontmostViewController!")
                            return
                        }

                        ContactSupportActionSheet.present(
                            emailFilter: .custom("BackupSubscriptionAlreadyRedeemed"),
                            logDumper: .fromGlobals(),
                            fromViewController: frontmostViewController,
                        )
                    }
                }),
            ),
        )
    }
}
