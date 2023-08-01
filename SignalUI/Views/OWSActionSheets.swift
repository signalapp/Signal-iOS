//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging

public enum OWSActionSheets {
    public static func showActionSheet(
        _ actionSheet: ActionSheetController,
        fromViewController: UIViewController? = nil
    ) {
        guard let fromViewController = fromViewController ?? CurrentAppContext().frontmostViewController() else {
            owsFailDebug("frontmostViewController was unexpectedly nil")
            return
        }
        fromViewController.present(actionSheet, animated: true, completion: nil)
    }

    public static func showActionSheet(
        title: String? = nil,
        message: String? = nil,
        buttonTitle: String? = nil,
        buttonAction: ActionSheetAction.Handler? = nil,
        fromViewController: UIViewController? = nil
    ) {
        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addOkayAction(title: buttonTitle, action: buttonAction)
        showActionSheet(actionSheet, fromViewController: fromViewController)
    }

    public static func showActionSheet(
        title: String? = nil,
        message: NSAttributedString,
        buttonTitle: String? = nil,
        buttonAction: ActionSheetAction.Handler? = nil,
        fromViewController: UIViewController? = nil
    ) {
        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addOkayAction(title: buttonTitle, action: buttonAction)
        showActionSheet(actionSheet, fromViewController: fromViewController)
    }

    public static func showConfirmationAlert(
        title: String? = nil,
        message: String? = nil,
        proceedTitle: String? = nil,
        proceedStyle: ActionSheetAction.Style = .default,
        proceedAction: @escaping ActionSheetAction.Handler
    ) {
        assert(!title.isEmptyOrNil || !message.isEmptyOrNil)

        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(self.cancelAction)

        let actionTitle = proceedTitle ?? CommonStrings.okButton
        let okAction = ActionSheetAction(
            title: actionTitle,
            accessibilityIdentifier: "OWSActionSheets.ok",
            style: proceedStyle,
            handler: proceedAction
        )
        actionSheet.addAction(okAction)

        CurrentAppContext().frontmostViewController()?.present(actionSheet, animated: true)
    }

    public static func showConfirmationWithNotNowAlert(
        title: String? = nil,
        message: String? = nil,
        proceedTitle: String? = nil,
        proceedStyle: ActionSheetAction.Style = .default,
        proceedAction: @escaping ActionSheetAction.Handler
    ) {
        assert(!title.isEmptyOrNil || message.isEmptyOrNil)

        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(self.notNowAction)

        let actionTitle = proceedTitle ?? CommonStrings.okButton
        let okAction = ActionSheetAction(
            title: actionTitle,
            accessibilityIdentifier: "OWSActionSheets.ok",
            style: proceedStyle,
            handler: proceedAction
        )
        actionSheet.addAction(okAction)

        CurrentAppContext().frontmostViewController()?.present(actionSheet, animated: true)
    }

    public static func showErrorAlert(
        message: String,
        fromViewController: UIViewController? = nil
    ) {
        showActionSheet(
            title: CommonStrings.errorAlertTitle,
            message: message,
            fromViewController: fromViewController
        )
    }

    public static var okayAction: ActionSheetAction {
        let action = ActionSheetAction(
            title: CommonStrings.okButton,
            accessibilityIdentifier: "OWSActionSheets.okay",
            style: .cancel
        ) { _ in
            Logger.debug("Okay item")
            // Do nothing.
        }
        return action
    }

    public static var cancelAction: ActionSheetAction {
        let action = ActionSheetAction(
            title: CommonStrings.cancelButton,
            accessibilityIdentifier: "OWSActionSheets.cancel",
            style: .cancel
        ) { _ in
            Logger.debug("Cancel item")
            // Do nothing.
        }
        return action
    }

    public static var notNowAction: ActionSheetAction {
        let action = ActionSheetAction(
            title: CommonStrings.notNowButton,
            accessibilityIdentifier: "OWSActionSheets.notNow",
            style: .cancel
        ) { _ in
            Logger.debug("Not now item")
            // Do nothing.
        }
        return action
    }

    public static var dismissAction: ActionSheetAction {
        let action = ActionSheetAction(
            title: CommonStrings.dismissButton,
            accessibilityIdentifier: "OWSActionSheets.dismiss",
            style: .cancel
        ) { _ in
            Logger.debug("Dismiss item")
            // Do nothing.
        }
        return action
    }

    public static func showPendingChangesActionSheet(discardAction: @escaping () -> Void) {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString("PENDING_CHANGES_ACTION_SHEET_TITLE",
                                      comment: "The alert title if user tries to exit a task without saving changes."),
            message: OWSLocalizedString("PENDING_CHANGES_ACTION_SHEET_MESSAGE",
                                        comment: "The alert message if user tries to exit a task without saving changes.")
        )

        let discardAction = ActionSheetAction(
            title: OWSLocalizedString("ALERT_DISCARD_BUTTON",
                                      comment: "The label for the 'discard' button in alerts and action sheets."),
            accessibilityIdentifier: "OWSActionSheets.discard",
            style: .destructive
        ) { _ in discardAction() }
        actionSheet.addAction(discardAction)
        actionSheet.addAction(OWSActionSheets.cancelAction)

        OWSActionSheets.showActionSheet(actionSheet)
    }
}

fileprivate extension ActionSheetController {
    func addOkayAction(title: String? = nil, action: ActionSheetAction.Handler? = nil) {
        let actionTitle = title ?? CommonStrings.okButton
        let okAction = ActionSheetAction(title: actionTitle, style: .default, handler: action)
        okAction.accessibilityIdentifier = "OWSActionSheets.\("ok")"
        addAction(okAction)
    }
}
