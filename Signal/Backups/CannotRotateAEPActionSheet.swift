//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class CannotRotateAEPActionSheet: ActionSheetController {
    init?(restrictions: RotateAEPRestrictions, fromViewController: UIViewController) {
        let message: String
        let primaryButtonTitle: String
        let primaryButtonAction: () -> Void

        // Only show one restriction at a time, so we can direct the user to that settings page.
        if restrictions.contains(.localFileBackupsEnabled) {
            message = OWSLocalizedString(
                "AEP_MANAGER_LOCAL_BACKUPS_DISABLE_REQUIRED",
                comment: "Message shown in an action sheet when attempting to rotate AEP, but local backups is enabled.",
            )
            primaryButtonTitle = OWSLocalizedString(
                "AEP_MANAGER_ON_DEVICE_BACKUP_SETTINGS_BUTTON",
                comment: "Button in an action sheet that takes the user to On-Device Backup settings.",
            )
            primaryButtonAction = { [weak fromViewController] in
                fromViewController?.dismiss(animated: true) {
                    SignalApp.shared.showAppSettings(mode: .backups(page: .local))
                }
            }
        } else if restrictions.contains(.remoteBackupsEnabled) {
            message = OWSLocalizedString(
                "ROTATE_AEP_ACTION_BACKUPS_DISABLE_REQUIRED",
                comment: "Message shown in an action sheet when attempting to disable PIN, but Backups is enabled.",
            )
            primaryButtonTitle = OWSLocalizedString(
                "BACKUP_SETTINGS_LANDING_VIEW_SETTINGS_BUTTON",
                comment: "Button to view settings for remote backups on the Backups settings landing page.",
            )
            primaryButtonAction = { [weak fromViewController] in
                fromViewController?.dismiss(animated: true) {
                    SignalApp.shared.showAppSettings(mode: .backups(page: .remote()))
                }
            }
        } else {
            owsFailDebug("Should not present CannotRotateAEPActionSheet when result is .success")
            return nil
        }

        super.init()
        setTitle(nil, message: message)
        addAction(ActionSheetAction(
            title: primaryButtonTitle,
            handler: { _ in primaryButtonAction() },
        ))
        addAction(.ok)
    }
}
