//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class BackupsBackUpYourMediaMegaphone: Megaphone {
    init(
        backupSubscriptionConfiguration: BackupSubscriptionConfiguration,
        experienceUpgrade: ExperienceUpgrade,
        fromViewController: UIViewController,
    ) {
        super.init(experienceUpgrade: experienceUpgrade)

        let storageAllowanceBytesFormatted = backupSubscriptionConfiguration.storageAllowanceBytes
            .formatted(.owsByteCount(
                fudgeBase2ToBase10: true,
                zeroPadFractionDigits: false,
            ))

        titleText = OWSLocalizedString(
            "BACKUPS_BACK_UP_YOUR_MEDIA_MEGAPHONE_TITLE",
            comment: "Title for a megaphone shown on the chat list encouraging users to subscribe to a paid Backup plan to back up all their media.",
        )
        bodyText = String.nonPluralLocalizedStringWithFormat(
            OWSLocalizedString(
                "BACKUPS_BACK_UP_YOUR_MEDIA_MEGAPHONE_BODY",
                comment: "Body for a megaphone shown on the chat list encouraging users to subscribe to a paid Backup plan to back up all their media. Embeds {{ the amount of storage included in the paid plan, preformatted as a localized byte count, e.g. '100 GB' }}.",
            ),
            storageAllowanceBytesFormatted,
        )
        image = .backupsMegaphoneAlbum

        let primaryButton = Button(
            title: OWSLocalizedString(
                "BACKUPS_BACK_UP_YOUR_MEDIA_MEGAPHONE_PRIMARY_ACTION",
                comment: "Title for a button on a megaphone encouraging users to subscribe to a paid Backup plan to back up all their media.",
            ),
            action: {
                SignalApp.shared.showAppSettings(mode: .backups(onAppearAction: .presentBackupPlanUpsell(
                    titleTextBuilder: { _ in
                        OWSLocalizedString(
                            "BACKUPS_BACK_UP_YOUR_MEDIA_UPSELL_TITLE",
                            comment: "Title for a Backup plan upsell view encouraging users to subscribe to a paid Backup plan to back up all their media.",
                        )
                    },
                    bodyTextBuilder: { _ in
                        String.nonPluralLocalizedStringWithFormat(
                            OWSLocalizedString(
                                "BACKUPS_BACK_UP_YOUR_MEDIA_UPSELL_BODY",
                                comment: "Body for a Backup plan upsell view encouraging users to subscribe to a paid Backup plan to back up all their media. Embeds {{ the amount of storage included in the paid plan, preformatted as a localized byte count, e.g. '100 GB' }}.",
                            ),
                            storageAllowanceBytesFormatted,
                        )
                    },
                )))
            },
        )

        let secondaryButton = snoozeButton(
            fromViewController: fromViewController,
            snoozeTitle: CommonStrings.notNowButton,
        )

        buttons = [primaryButton, secondaryButton]
    }
}
