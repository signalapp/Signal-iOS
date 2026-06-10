//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

class BackupsNeverLoseAMessageMegaphone: Megaphone {
    init(
        experienceUpgrade: ExperienceUpgrade,
        fromViewController: UIViewController,
    ) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = OWSLocalizedString(
            "BACKUPS_NEVER_LOSE_A_MESSAGE_MEGAPHONE_TITLE",
            comment: "Title for a megaphone shown on the chat list encouraging users to enable Signal Secure Backups.",
        )
        bodyText = OWSLocalizedString(
            "BACKUPS_NEVER_LOSE_A_MESSAGE_MEGAPHONE_BODY",
            comment: "Body for a megaphone shown on the chat list encouraging users to enable Signal Secure Backups.",
        )
        image = .backupsMegaphoneMessageBubbles

        let primaryButton = Megaphone.Button(
            title: OWSLocalizedString(
                "BACKUPS_NEVER_LOSE_A_MESSAGE_MEGAPHONE_PRIMARY_ACTION",
                comment: "Title for a button on a megaphone encouraging users to enable Signal Secure Backups.",
            ),
            action: {
                SignalApp.shared.showAppSettings(mode: .backups(onAppearAction: nil))
            },
        )

        let secondaryButton = snoozeButton(
            fromViewController: fromViewController,
            snoozeTitle: CommonStrings.notNowButton,
        )

        buttons = [primaryButton, secondaryButton]
    }
}
