//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

@objc
public class OWSActionSheets: NSObject {

    @objc
    public class func showActionSheet(_ actionSheet: ActionSheetController, fromViewController: UIViewController? = nil) {
        guard let fromViewController = fromViewController ?? CurrentAppContext().frontmostViewController() else {
            owsFailDebug("frontmostViewController was unexpectedly nil")
            return
        }
        fromViewController.present(actionSheet, animated: true, completion: nil)
    }

    @objc
    public class func showActionSheet(title: String) {
        self.showActionSheet(title: title, message: nil, buttonTitle: nil)
    }

    @objc
    public class func showActionSheet(title: String?, message: String) {
        self.showActionSheet(title: title, message: message, buttonTitle: nil)
    }

    @objc
    public class func showActionSheet(title: String? = nil, message: String? = nil, buttonTitle: String? = nil, buttonAction: ActionSheetAction.Handler? = nil) {
        guard let fromViewController = CurrentAppContext().frontmostViewController() else {
            return
        }
        showActionSheet(title: title, message: message, buttonTitle: buttonTitle, buttonAction: buttonAction,
                  fromViewController: fromViewController)
    }

    @objc
    public class func showActionSheet(title: String? = nil, message: String? = nil, buttonTitle: String? = nil, buttonAction: ActionSheetAction.Handler? = nil, fromViewController: UIViewController?) {

        let actionSheet = ActionSheetController(title: title, message: message)

        let actionTitle = buttonTitle ?? CommonStrings.okButton
        let okAction = ActionSheetAction(title: actionTitle, style: .default, handler: buttonAction)
        okAction.accessibilityIdentifier = "OWSActionSheets.\("ok")"
        actionSheet.addAction(okAction)
        fromViewController?.presentActionSheet(actionSheet)
    }

    @objc
    public class func showConfirmationAlert(title: String, message: String? = nil, proceedTitle: String? = nil, proceedStyle: ActionSheetAction.Style = .default, proceedAction: @escaping ActionSheetAction.Handler) {
        assert(title.count > 0)

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

    @objc
    public class func showConfirmationWithNotNowAlert(title: String, message: String? = nil, proceedTitle: String? = nil, proceedStyle: ActionSheetAction.Style = .default, proceedAction: @escaping ActionSheetAction.Handler) {
        assert(title.count > 0)

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

    @objc
    public class func showErrorAlert(message: String) {
        self.showActionSheet(title: CommonStrings.errorAlertTitle, message: message, buttonTitle: nil)
    }

    @objc
    public class var okayAction: ActionSheetAction {
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

    @objc
    public class var cancelAction: ActionSheetAction {
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

    @objc
    public class var notNowAction: ActionSheetAction {
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

    @objc
    public class var dismissAction: ActionSheetAction {
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

    @objc
    public class func showPendingChangesActionSheet(discardAction: @escaping () -> Void) {
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
