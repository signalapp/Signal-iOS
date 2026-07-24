//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class LocalFileBackupSelectFolderHeroSheetViewController: HeroSheetViewController {
    init(onContinue: @escaping () -> Void) {
        super.init(
            hero: .image(.folder, tintColor: .Signal.label),
            title: OWSLocalizedString(
                "LOCAL_FILE_BACKUPS_CHOOSE_FOLDER_TITLE",
                comment: "Title text for a sheet telling the user to choose a folder to store their Signal on-device backup.",
            ),
            body: HeroSheetViewController.Body([
                .text(
                    .plain(
                        OWSLocalizedString(
                            "LOCAL_FILE_BACKUPS_CHOOSE_FOLDER_BODY",
                            comment: "Body text for a sheet telling the user to choose a folder to store their Signal on-device backup.",
                        ),
                    ),
                    alignment: .center,
                    color: UIColor.Signal.secondaryLabel,
                ),
            ]),
            primary: .button(HeroSheetViewController.Button(
                title: OWSLocalizedString(
                    "LOCAL_FILE_BACKUPS_CHOOSE_FOLDER_BUTTON",
                    comment: "Button for a sheet asking the user to choose a folder to save their local backup in.",
                ),
                style: .primary,
                action: .custom({ heroSheet in
                    heroSheet.dismiss(animated: true)
                    onContinue()
                }),
            )),
            secondary: .button(
                .dismissing(
                    title: CommonStrings.cancelButton,
                    style: .secondary,
                ),
            ),
        )
    }
}
