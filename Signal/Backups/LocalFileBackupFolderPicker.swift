//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

enum LocalFileBackupArchiveFolderPicker {
    static func present(
        fromViewController: UIViewController,
        manager: LocalFileBackupManager,
        onSuccess: @escaping () -> Void,
        onCancel: (() -> Void)? = nil,
    ) {
        manager.promptUserToChooseFileLocationForArchiving(
            fromViewController: fromViewController,
            completion: { [self] result in
                switch result {
                case .picked:
                    onSuccess()
                case .cancelled:
                    onCancel?()
                case .failed(let chooseError):
                    Logger.error("Error choosing file location for local backup: \(chooseError.shortDescription)")
                    let actionSheet = LocalFileBackupChooseFolderErrorActionSheet(
                        fromViewController: fromViewController,
                        onTryAgain: {
                            present(fromViewController: fromViewController, manager: manager, onSuccess: onSuccess, onCancel: onCancel)
                        },
                    )
                    fromViewController.presentActionSheet(actionSheet)
                }
            },
        )
    }
}
