//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc public class OWSActionSheets: NSObject {

    @objc
    public class func showActionSheet(_ actionSheet: ActionSheetController) {
        guard let frontmostViewController = CurrentAppContext().frontmostViewController() else {
            owsFailDebug("frontmostViewController was unexpectedly nil")
            return
        }
        frontmostViewController.present(actionSheet, animated: true, completion: nil)
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
    public class func showActionSheet(title: String?, message: String? = nil, buttonTitle: String? = nil, buttonAction: ActionSheetAction.Handler? = nil) {
        guard let fromViewController = CurrentAppContext().frontmostViewController() else {
            return
        }
        showActionSheet(title: title, message: message, buttonTitle: buttonTitle, buttonAction: buttonAction,
                  fromViewController: fromViewController)
    }

    @objc
    public class func showActionSheet(title: String?, message: String? = nil, buttonTitle: String? = nil, buttonAction: ActionSheetAction.Handler? = nil, fromViewController: UIViewController?) {

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
    public class func showErrorAlert(message: String) {
        self.showActionSheet(title: CommonStrings.errorAlertTitle, message: message, buttonTitle: nil)
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
            title: NSLocalizedString("NEW_GROUP_VIEW_UNSAVED_CHANGES_TITLE",
                                     comment: "The alert title if user tries to exit the new group view without saving changes."),
            message: NSLocalizedString("NEW_GROUP_VIEW_UNSAVED_CHANGES_MESSAGE",
                                       comment: "The alert message if user tries to exit the new group view without saving changes.")
        )

        let discardAction = ActionSheetAction(
            title: NSLocalizedString("ALERT_DISCARD_BUTTON",
                                     comment: "The label for the 'discard' button in alerts and action sheets."),
            accessibilityIdentifier: "OWSActionSheets.discard",
            style: .destructive
        ) { _ in discardAction() }
        actionSheet.addAction(discardAction)
        actionSheet.addAction(OWSActionSheets.cancelAction)

        OWSActionSheets.showActionSheet(actionSheet)
    }

    @objc
    public class func showIOSUpgradeNagIfNecessary() {
        // We want to nag iOS 10 users now that we're bumping up
        // our min SDK to iOS 11.
        if #available(iOS 11.0, *) { return }

        // Don't show the nag to users who have just launched
        // the app for the first time.
        guard AppVersion.shared().lastAppVersion != nil else {
            return
        }

        if let iOSUpgradeNagDate = Environment.shared.preferences.iOSUpgradeNagDate() {
            let kNagFrequencySeconds = 3 * kDayInterval
            guard fabs(iOSUpgradeNagDate.timeIntervalSinceNow) > kNagFrequencySeconds else {
                return
            }
        }

        Environment.shared.preferences.setIOSUpgradeNagDate(Date())

        OWSActionSheets.showActionSheet(title: NSLocalizedString("UPGRADE_IOS_ALERT_TITLE",
                                                        comment: "Title for the alert indicating that user should upgrade iOS."),
                            message: NSLocalizedString("UPGRADE_IOS_ALERT_MESSAGE",
                                                      comment: "Message for the alert indicating that user should upgrade iOS."))
    }
}
