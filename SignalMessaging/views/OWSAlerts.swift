//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc public class OWSAlerts: NSObject {
    let TAG = "[OWSAlerts]"

    /// Cleanup and present alert for no permissions
    @objc
    public class func showNoMicrophonePermissionAlert() {
        let alertTitle = NSLocalizedString("CALL_AUDIO_PERMISSION_TITLE", comment:"Alert title when calling and permissions for microphone are missing")
        let alertMessage = NSLocalizedString("CALL_AUDIO_PERMISSION_MESSAGE", comment:"Alert message when calling and permissions for microphone are missing")
        let alertController = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)
        let dismissAction = UIAlertAction(title: CommonStrings.dismissButton, style: .cancel)
        let settingsString = CommonStrings.openSettingsButton
        let settingsAction = UIAlertAction(title: settingsString, style: .default) { _ in
            CurrentAppContext().openSystemSettings()
        }
        alertController.addAction(dismissAction)
        alertController.addAction(settingsAction)
        CurrentAppContext().frontmostViewController()?.present(alertController, animated: true, completion: nil)
    }

    @objc
    public class func showAlert(withTitle title: String) {
        self.showAlert(withTitle: title, message: nil, buttonTitle: nil)
    }

    @objc
    public class func showAlert(withTitle title: String, message: String) {
        self.showAlert(withTitle: title, message: message, buttonTitle: nil)
    }

    @objc
    public class func showAlert(withTitle title: String, message: String? = nil, buttonTitle: String? = nil, buttonAction: ((UIAlertAction) -> Void)? = nil) {
        assert(title.count > 0)

        let actionTitle = buttonTitle ?? NSLocalizedString("OK", comment: "")

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: actionTitle, style: .default, handler: buttonAction))
        CurrentAppContext().frontmostViewController()?.present(alert, animated: true, completion: nil)
    }

    @objc
    public class func showConfirmationAlert(withTitle title: String, message: String? = nil, proceedTitle: String? = nil, proceedAction: @escaping (UIAlertAction) -> Void) {
        assert(title.count > 0)

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(self.cancelAction)

        let actionTitle = proceedTitle ?? NSLocalizedString("OK", comment: "")
        alert.addAction(UIAlertAction(title: actionTitle, style: .default, handler: proceedAction))

        CurrentAppContext().frontmostViewController()?.present(alert, animated: true, completion: nil)
    }

    @objc
    public class var cancelAction: UIAlertAction {
        let action = UIAlertAction(title: CommonStrings.cancelButton, style: .cancel) { _ in
            Logger.debug("Cancel item")
            // Do nothing.
        }
        return action
    }

}
