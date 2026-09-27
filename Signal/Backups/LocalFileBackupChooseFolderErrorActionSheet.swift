//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class LocalFileBackupChooseFolderErrorActionSheet: ActionSheetController {
    init(fromViewController: UIViewController, onTryAgain: @escaping () -> Void) {
        super.init()
        setTitle(
            OWSLocalizedString(
                "LOCAL_FILE_BACKUP_CHOOSE_FOLDER_ERROR_TITLE",
                comment: "Title for an action sheet informing the user we were unable to save their local backup location",
            ),
            message: OWSLocalizedString(
                "LOCAL_FILE_BACKUP_CHOOSE_FOLDER_ERROR_MESSAGE",
                comment: "Message for an action sheet informing the user we were unable to save their local backup location",
            ),
        )
        addAction(
            ActionSheetAction(
                title: CommonStrings.tryAgainButton,
                handler: { _ in
                    onTryAgain()
                },
            ),
        )
        addAction(
            .contactSupport(
                emailFilter: .custom("iOS Local Backup Choose Backup Location Failed"),
                fromViewController: fromViewController,
            ),
        )
        addAction(.cancel)
    }
}
