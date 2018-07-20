//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc public class OWSAlerts: NSObject {

    /// Cleanup and present alert for no permissions
    @objc
    public class func showNoMicrophonePermissionAlert() {
        let alertTitle = NSLocalizedString("CALL_AUDIO_PERMISSION_TITLE", comment: "Alert title when calling and permissions for microphone are missing")
        let alertMessage = NSLocalizedString("CALL_AUDIO_PERMISSION_MESSAGE", comment: "Alert message when calling and permissions for microphone are missing")
        let alertController = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)
        let dismissAction = UIAlertAction(title: CommonStrings.dismissButton, style: .cancel)

        alertController.addAction(dismissAction)
        if let settingsAction = CurrentAppContext().openSystemSettingsAction {
            alertController.addAction(settingsAction)
        }
        CurrentAppContext().frontmostViewController()?.present(alertController, animated: true, completion: nil)
    }

    @objc
    public class func showAlert(_ alert: UIAlertController) {
        guard let frontmostViewController = CurrentAppContext().frontmostViewController() else {
            owsFailDebug("frontmostViewController was unexpectedly nil")
            return
        }
        frontmostViewController.present(alert, animated: true, completion: nil)
    }

    @objc
    public class func showAlert(title: String) {
        self.showAlert(title: title, message: nil, buttonTitle: nil)
    }

    @objc
    public class func showAlert(title: String?, message: String) {
        self.showAlert(title: title, message: message, buttonTitle: nil)
    }

    @objc
    public class func showAlert(title: String?, message: String? = nil, buttonTitle: String? = nil, buttonAction: ((UIAlertAction) -> Void)? = nil) {
        guard let fromViewController = CurrentAppContext().frontmostViewController() else {
            return
        }
        showAlert(title: title, message: message, buttonTitle: buttonTitle, buttonAction: buttonAction,
                  fromViewController: fromViewController)
    }

    @objc
    public class func showAlert(title: String?, message: String? = nil, buttonTitle: String? = nil, buttonAction: ((UIAlertAction) -> Void)? = nil, fromViewController: UIViewController?) {
        let actionTitle = buttonTitle ?? NSLocalizedString("OK", comment: "")

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: actionTitle, style: .default, handler: buttonAction))
        fromViewController?.present(alert, animated: true, completion: nil)
    }

    @objc
    public class func showConfirmationAlert(title: String, message: String? = nil, proceedTitle: String? = nil, proceedAction: @escaping (UIAlertAction) -> Void) {
        assert(title.count > 0)

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(self.cancelAction)

        let actionTitle = proceedTitle ?? NSLocalizedString("OK", comment: "")
        alert.addAction(UIAlertAction(title: actionTitle, style: .default, handler: proceedAction))

        CurrentAppContext().frontmostViewController()?.present(alert, animated: true, completion: nil)
    }

    @objc
    public class func showErrorAlert(message: String) {
        self.showAlert(title: CommonStrings.errorAlertTitle, message: message, buttonTitle: nil)
    }

    @objc
    public class var cancelAction: UIAlertAction {
        let action = UIAlertAction(title: CommonStrings.cancelButton, style: .cancel) { _ in
            Logger.debug("Cancel item")
            // Do nothing.
        }
        return action
    }

    @objc
    public class func showIOSUpgradeNagIfNecessary() {
        // Only show the nag to iOS 8 users.
        //
        // NOTE: Our current minimum iOS version is 9, so this should never show.
        if #available(iOS 9.0, *) {
            return
        }

        // Don't show the nag to users who have just launched
        // the app for the first time.
        guard AppVersion.sharedInstance().lastAppVersion != nil else {
            return
        }

        if let iOSUpgradeNagDate = Environment.shared.preferences.iOSUpgradeNagDate() {
            // Nag no more than once every three days.
            let kNagFrequencySeconds = 3 * kDayInterval
            guard fabs(iOSUpgradeNagDate.timeIntervalSinceNow) > kNagFrequencySeconds else {
                return
            }
        }

        Environment.shared.preferences.setIOSUpgradeNagDate(Date())

        OWSAlerts.showAlert(title: NSLocalizedString("UPGRADE_IOS_ALERT_TITLE",
                                                        comment: "Title for the alert indicating that user should upgrade iOS."),
                            message: NSLocalizedString("UPGRADE_IOS_ALERT_MESSAGE",
                                                      comment: "Message for the alert indicating that user should upgrade iOS."))
    }
}
