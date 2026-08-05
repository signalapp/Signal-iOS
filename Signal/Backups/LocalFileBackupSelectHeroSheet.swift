//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class LocalFileBackupSelectHeroSheet: HeroSheetViewController {
    init(
        onChooseBackup: @escaping () -> Void,
    ) {
        super.init(
            hero: .circleIcon(
                icon: .folder,
                iconSize: 40,
                tintColor: UIColor(rgbHex: 0x3B45FD),
                backgroundColor: UIColor(rgbHex: 0xE0E5FF),
            ),
            title: OWSLocalizedString(
                "LOCAL_BACKUPS_SELECT_HERO_SHEET_TITLE",
                comment: "Title for a sheet asking the user to select their backup to restore from during registration.",
            ),
            body: HeroSheetViewController.Body([
                .text(
                    .plain(OWSLocalizedString(
                        "LOCAL_BACKUPS_SELECT_HERO_SHEET_BODY",
                        comment: "Body text for a sheet asking the user to select their backup to restore from during registration.",
                    )),
                    alignment: .center,
                    color: .Signal.secondaryLabel,
                ),
                .bullets(spacing: 32, [
                    HeroSheetViewController.Body.BulletPoint(
                        icon: .lock,
                        text: OWSLocalizedString(
                            "LOCAL_BACKUPS_SELECT_HERO_SHEET_BULLET_1",
                            comment: "Bullet point for a sheet asking the user to select their backup to restore from during registration.",
                        ),
                    ),
                    HeroSheetViewController.Body.BulletPoint(
                        icon: .tapHand,
                        text: OWSLocalizedString(
                            "LOCAL_BACKUPS_SELECT_HERO_SHEET_BULLET_2",
                            comment: "Bullet point for a sheet asking the user to select their backup to restore from during registration.",
                        ),
                    ),
                    HeroSheetViewController.Body.BulletPoint(
                        icon: .errorCircle,
                        text: OWSLocalizedString(
                            "LOCAL_BACKUPS_SELECT_HERO_SHEET_BULLET_3",
                            comment: "Bullet point for a sheet asking the user to select their backup to restore from during registration.",
                        ),
                    ),
                ]),
            ]),
            primary: .button(Button(title: CommonStrings.continueButton, action: { heroSheet in
                heroSheet.dismiss(animated: true)
                onChooseBackup()
            })),
            secondary: nil,
        )
    }
}
