//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public enum OWSActionSheets {
    public static func showActionSheet(
        _ actionSheet: ActionSheetController,
        fromViewController: UIViewController? = nil,
    ) {
        guard let fromViewController = fromViewController ?? CurrentAppContext().frontmostViewController() else {
            owsFailDebug("frontmostViewController was unexpectedly nil")
            return
        }
        fromViewController.present(actionSheet, animated: true, completion: nil)
    }

    /// Present the given action sheet, resuming when it is dismissed.
    ///
    /// Overwrites the action sheet's `onDismiss`.
    @MainActor
    public static func showAndAwaitActionSheet(
        _ actionSheet: ActionSheetController,
        fromViewController: UIViewController? = nil,
    ) async {
        await withCheckedContinuation { continuation in
            actionSheet.onDismiss = { continuation.resume() }
            showActionSheet(actionSheet, fromViewController: fromViewController)
        }
    }

    public static func showActionSheet(
        title: String? = nil,
        message: String? = nil,
        buttonTitle: String? = nil,
        buttonAction: ActionSheetAction.Handler? = nil,
        fromViewController: UIViewController? = nil,
        dismissalDelegate: (any SheetDismissalDelegate)? = nil,
    ) {
        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addOkayAction(title: buttonTitle, action: buttonAction)
        actionSheet.dismissalDelegate = dismissalDelegate
        showActionSheet(actionSheet, fromViewController: fromViewController)
    }

    public static func showActionSheet(
        title: String? = nil,
        message: NSAttributedString,
        buttonTitle: String? = nil,
        buttonAction: ActionSheetAction.Handler? = nil,
        fromViewController: UIViewController? = nil,
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
        proceedAction: @escaping ActionSheetAction.Handler,
        fromViewController: UIViewController? = nil,
        dismissalDelegate: (any SheetDismissalDelegate)? = nil,
    ) {
        assert(!title.isEmptyOrNil || !message.isEmptyOrNil)

        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(self.cancelAction)

        let actionTitle = proceedTitle ?? CommonStrings.okButton
        let okAction = ActionSheetAction(
            title: actionTitle,
            style: proceedStyle,
            handler: proceedAction,
        )
        actionSheet.addAction(okAction)
        actionSheet.dismissalDelegate = dismissalDelegate

        showActionSheet(actionSheet, fromViewController: fromViewController)
    }

    public static func showConfirmationWithNotNowAlert(
        title: String? = nil,
        message: String? = nil,
        proceedTitle: String? = nil,
        proceedStyle: ActionSheetAction.Style = .default,
        proceedAction: @escaping ActionSheetAction.Handler,
    ) {
        assert(!title.isEmptyOrNil || message.isEmptyOrNil)

        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(self.notNowAction)

        let actionTitle = proceedTitle ?? CommonStrings.okButton
        let okAction = ActionSheetAction(
            title: actionTitle,
            style: proceedStyle,
            handler: proceedAction,
        )
        actionSheet.addAction(okAction)

        CurrentAppContext().frontmostViewController()?.present(actionSheet, animated: true)
    }

    public static func showErrorAlert(
        message: String,
        fromViewController: UIViewController? = nil,
        dismissalDelegate: (any SheetDismissalDelegate)? = nil,
    ) {
        showActionSheet(
            title: CommonStrings.errorAlertTitle,
            message: message,
            fromViewController: fromViewController,
            dismissalDelegate: dismissalDelegate,
        )
    }

    public static var okayAction: ActionSheetAction {
        return ActionSheetAction(
            title: CommonStrings.okButton,
            style: .cancel,
            handler: nil,
        )
    }

    public static var cancelAction: ActionSheetAction {
        return ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel,
            handler: nil,
        )
    }

    public static var notNowAction: ActionSheetAction {
        let action = ActionSheetAction(
            title: CommonStrings.notNowButton,
            style: .cancel,
        ) { _ in
            Logger.debug("Not now item")
            // Do nothing.
        }
        return action
    }

    public static var dismissAction: ActionSheetAction {
        let action = ActionSheetAction(
            title: CommonStrings.dismissButton,
            style: .cancel,
        ) { _ in
            Logger.debug("Dismiss item")
            // Do nothing.
        }
        return action
    }

    public static func showPendingChangesActionSheet(discardAction: @escaping () -> Void) {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "PENDING_CHANGES_ACTION_SHEET_TITLE",
                comment: "The alert title if user tries to exit a task without saving changes.",
            ),
            message: OWSLocalizedString(
                "PENDING_CHANGES_ACTION_SHEET_MESSAGE",
                comment: "The alert message if user tries to exit a task without saving changes.",
            ),
        )

        let discardAction = ActionSheetAction(
            title: CommonStrings.discardButton,
            style: .destructive,
        ) { _ in discardAction() }
        actionSheet.addAction(discardAction)
        actionSheet.addAction(OWSActionSheets.cancelAction)

        OWSActionSheets.showActionSheet(actionSheet)
    }
}

private extension ActionSheetController {
    func addOkayAction(title: String? = nil, action: ActionSheetAction.Handler? = nil) {
        let actionTitle = title ?? CommonStrings.okButton
        let okAction = ActionSheetAction(title: actionTitle, style: .default, handler: action)
        addAction(okAction)
    }
}
