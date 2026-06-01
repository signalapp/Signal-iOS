//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class ContactPermissionReminderMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = OWSLocalizedString(
            "CONTACT_PERMISSION_REMINDER_MEGAPHONE_TITLE",
            comment: "Title for contact permission reminder megaphone",
        )
        bodyText = OWSLocalizedString(
            "CONTACT_PERMISSION_REMINDER_MEGAPHONE_BODY",
            comment: "Body for contact permission reminder megaphone",
        )
        image = .contacts

        let primaryButtonTitle = OWSLocalizedString(
            "CONTACT_PERMISSION_REMINDER_MEGAPHONE_ACTION",
            comment: "Action text for contact permission reminder megaphone",
        )

        let primaryButton = MegaphoneView.Button(title: primaryButtonTitle) {
            let actionSheetController = ActionSheetController()
            actionSheetController.isCancelable = true

            let turnOnView: TurnOnPermissionView
            if #available(iOS 18, *) {
                let imageConfig = UIImage.SymbolConfiguration(pointSize: 24.0)
                let image = UIImage(systemName: "checkmark", withConfiguration: imageConfig)!
                    .withRenderingMode(.alwaysTemplate)

                turnOnView = TurnOnPermissionView(
                    fromActionSheetController: actionSheetController,
                    title: OWSLocalizedString(
                        "CONTACT_PERMISSION_ACTION_SHEET_2_TITLE",
                        comment: "Title for contact permission action sheet",
                    ),
                    message: OWSLocalizedString(
                        "CONTACT_PERMISSION_ACTION_SHEET_2_BODY",
                        comment: "Body for contact permission action sheet",
                    ),
                    steps: [
                        .init(
                            icon: nil,
                            text: OWSLocalizedString(
                                "CONTACT_PERMISSION_ACTION_SHEET_2_STEP_ONE",
                                comment: "First step for contact permission action sheet",
                            ),
                        ),
                        .init(
                            icon: nil,
                            text: OWSLocalizedString(
                                "CONTACT_PERMISSION_ACTION_SHEET_2_STEP_TWO",
                                comment: "Second step for contact permission action sheet",
                            ),
                        ),
                        .init(
                            icon: image,
                            text: OWSLocalizedString(
                                "CONTACT_PERMISSION_ACTION_SHEET_2_STEP_THREE",
                                comment: "Third step for contact permission action sheet",
                            ),
                        ),
                    ],
                )
            } else {
                turnOnView = TurnOnPermissionView(
                    fromActionSheetController: actionSheetController,
                    title: OWSLocalizedString(
                        "CONTACT_PERMISSION_ACTION_SHEET_TITLE",
                        comment: "Title for contact permission action sheet",
                    ),
                    message: OWSLocalizedString(
                        "CONTACT_PERMISSION_ACTION_SHEET_BODY",
                        comment: "Body for contact permission action sheet",
                    ),
                    steps: [
                        .init(
                            icon: nil,
                            text: OWSLocalizedString(
                                "CONTACT_PERMISSION_ACTION_SHEET_STEP_ONE",
                                comment: "First step for contact permission action sheet",
                            ),
                        ),
                        .init(
                            icon: UIImage(imageLiteralResourceName: "toggle-32"),
                            text: OWSLocalizedString(
                                "CONTACT_PERMISSION_ACTION_SHEET_STEP_TWO",
                                comment: "Second step for contact permission action sheet",
                            ),
                        ),
                    ],
                )
            }

            actionSheetController.customHeader = turnOnView
            fromViewController.presentActionSheet(actionSheetController)
        }

        let secondaryButton = snoozeButton(
            fromViewController: fromViewController,
            snoozeTitle: OWSLocalizedString(
                "CONTACT_PERMISSION_NOT_NOW_ACTION",
                comment: "Snooze action text for contact permission reminder megaphone",
            ),
        )

        buttons = [primaryButton, secondaryButton]
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
