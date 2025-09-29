//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class ContactPermissionReminderMegaphone: MegaphoneView {
    weak var actionSheetController: ActionSheetController?

    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = OWSLocalizedString("CONTACT_PERMISSION_REMINDER_MEGAPHONE_TITLE",
                                      comment: "Title for contact permission reminder megaphone")
        bodyText = OWSLocalizedString("CONTACT_PERMISSION_REMINDER_MEGAPHONE_BODY",
                                     comment: "Body for contact permission reminder megaphone")
        imageName = "contacts"

        let primaryButtonTitle = OWSLocalizedString("CONTACT_PERMISSION_REMINDER_MEGAPHONE_ACTION",
                                                   comment: "Action text for contact permission reminder megaphone")

        let primaryButton = MegaphoneView.Button(title: primaryButtonTitle) { [weak self] in
            guard let self = self else { return }

            let turnOnView: TurnOnPermissionView
            if #available(iOS 18, *) {
                let imageConfig = UIImage.SymbolConfiguration(pointSize: 24.0)
                let image = UIImage(systemName: "checkmark", withConfiguration: imageConfig)!
                    .withRenderingMode(.alwaysTemplate)

                turnOnView = TurnOnPermissionView(
                    title: OWSLocalizedString(
                        "CONTACT_PERMISSION_ACTION_SHEET_2_TITLE",
                        comment: "Title for contact permission action sheet"
                    ),
                    message: OWSLocalizedString(
                        "CONTACT_PERMISSION_ACTION_SHEET_2_BODY",
                        comment: "Body for contact permission action sheet"
                    ),
                    steps: [
                        .init(
                            icon: nil,
                            text: OWSLocalizedString(
                                "CONTACT_PERMISSION_ACTION_SHEET_2_STEP_ONE",
                                comment: "First step for contact permission action sheet"
                            )
                        ),
                        .init(
                            icon: nil,
                            text: OWSLocalizedString(
                                "CONTACT_PERMISSION_ACTION_SHEET_2_STEP_TWO",
                                comment: "Second step for contact permission action sheet"
                            )
                        ),
                        .init(
                            icon: image,
                            text: OWSLocalizedString(
                                "CONTACT_PERMISSION_ACTION_SHEET_2_STEP_THREE",
                                comment: "Third step for contact permission action sheet"
                            )
                        )
                    ]
                )
            } else {
                turnOnView = TurnOnPermissionView(
                    title: OWSLocalizedString(
                        "CONTACT_PERMISSION_ACTION_SHEET_TITLE",
                        comment: "Title for contact permission action sheet"
                    ),
                    message: OWSLocalizedString(
                        "CONTACT_PERMISSION_ACTION_SHEET_BODY",
                        comment: "Body for contact permission action sheet"
                    ),
                    steps: [
                        .init(
                            icon: nil,
                            text: OWSLocalizedString(
                                "CONTACT_PERMISSION_ACTION_SHEET_STEP_ONE",
                                comment: "First step for contact permission action sheet"
                            )
                        ),
                        .init(
                            icon: UIImage(imageLiteralResourceName: "toggle-32"),
                            text: OWSLocalizedString(
                                "CONTACT_PERMISSION_ACTION_SHEET_STEP_TWO",
                                comment: "Second step for contact permission action sheet"
                            )
                        )
                    ]
                )
            }

            let actionSheetController = ActionSheetController()
            actionSheetController.customHeader = turnOnView
            actionSheetController.isCancelable = true
            fromViewController.presentActionSheet(actionSheetController)
            self.actionSheetController = actionSheetController
        }

        let secondaryButton = snoozeButton(
            fromViewController: fromViewController,
            snoozeTitle: OWSLocalizedString("CONTACT_PERMISSION_NOT_NOW_ACTION",
                                           comment: "Snooze action text for contact permission reminder megaphone")
        )
        setButtons(primary: primaryButton, secondary: secondaryButton)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        super.dismiss(animated: animated, completion: completion)
        actionSheetController?.dismiss(animated: animated)
    }
}
