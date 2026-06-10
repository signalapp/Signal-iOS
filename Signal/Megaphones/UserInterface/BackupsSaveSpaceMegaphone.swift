//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

class BackupsSaveSpaceMegaphone: Megaphone {
    init(
        areBackupsEnabled: Bool,
        experienceUpgrade: ExperienceUpgrade,
        fromViewController: UIViewController,
    ) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = OWSLocalizedString(
            "BACKUPS_SAVE_SPACE_MEGAPHONE_TITLE",
            comment: "Title for a megaphone shown on the chat list encouraging users to subscribe to a paid Backup plan to save on-device storage space.",
        )
        bodyText = OWSLocalizedString(
            "BACKUPS_SAVE_SPACE_MEGAPHONE_BODY",
            comment: "Body for a megaphone shown on the chat list encouraging users to subscribe to a paid Backup plan to save on-device storage space.",
        )
        image = .backupsMegaphoneData

        let primaryButton = Button(
            title: areBackupsEnabled
                ? OWSLocalizedString(
                    "BACKUPS_SAVE_SPACE_MEGAPHONE_PRIMARY_ACTION_UPGRADE",
                    comment: "Title for a button on a megaphone encouraging users to subscribe to a paid Backup plan to save on-device storage space, when the user already has Signal Secure Backups enabled.",
                )
                : OWSLocalizedString(
                    "BACKUPS_SAVE_SPACE_MEGAPHONE_PRIMARY_ACTION_TURN_ON",
                    comment: "Title for a button on a megaphone encouraging users to subscribe to a paid Backup plan to save on-device storage space, when the user does not yet have Signal Secure Backups enabled.",
                ),
            action: {
                SignalApp.shared.showAppSettings(mode: .backups(onAppearAction: .presentBackupPlanUpsell(
                    titleTextBuilder: { _ in
                        OWSLocalizedString(
                            "BACKUPS_SAVE_SPACE_UPSELL_TITLE",
                            comment: "Title for a Backup plan upsell view encouraging users to subscribe to a paid Backup plan to save on-device storage space.",
                        )
                    },
                    bodyTextBuilder: { tx in
                        let attachmentStore = AttachmentStore()

                        let attachmentsConsumingBytes = attachmentStore.sumEncryptedByteCount(
                            stopAfter: .max,
                            tx: tx,
                        )

                        // We only need to render gigabytes, and using a MeasurementFormatter
                        // directly gives us control over the number of decimal
                        // places (vs. ByteCountFormatter).
                        let formatter = MeasurementFormatter()
                        formatter.unitOptions = .providedUnit
                        formatter.numberFormatter.minimumFractionDigits = 0
                        formatter.numberFormatter.maximumFractionDigits = 1

                        let attachmentsConsumingGigabytes = Measurement(
                            value: Double(attachmentsConsumingBytes) / Double(UInt64.gigabyte),
                            unit: UnitInformationStorage.gigabytes,
                        )
                        let attachmentsConsumingBytesFormatted = formatter.string(
                            from: attachmentsConsumingGigabytes,
                        )

                        return String.nonPluralLocalizedStringWithFormat(
                            OWSLocalizedString(
                                "BACKUPS_SAVE_SPACE_UPSELL_BODY",
                                comment: "Body for a Backup plan upsell view encouraging users to subscribe to a paid Backup plan to save on-device storage space. Embeds {{ the amount of storage space being consumed on-device by media, preformatted as a localized byte count, e.g. '1.2 GB' }}.",
                            ),
                            attachmentsConsumingBytesFormatted,
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
