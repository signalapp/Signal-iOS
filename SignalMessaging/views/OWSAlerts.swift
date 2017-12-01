//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc class OWSAlerts: NSObject {
    let TAG = "[OWSAlerts]"

    /// Cleanup and present alert for no permissions
    public class func showNoMicrophonePermissionAlert() {
        let alertTitle = NSLocalizedString("CALL_AUDIO_PERMISSION_TITLE", comment:"Alert title when calling and permissions for microphone are missing")
        let alertMessage = NSLocalizedString("CALL_AUDIO_PERMISSION_MESSAGE", comment:"Alert message when calling and permissions for microphone are missing")
        let alertController = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)
        let dismissAction = UIAlertAction(title: CommonStrings.dismissButton, style: .cancel)
        let settingsString = NSLocalizedString("OPEN_SETTINGS_BUTTON", comment: "Button text which opens the settings app")
        let settingsAction = UIAlertAction(title: settingsString, style: .default) { _ in
            UIApplication.shared.openSystemSettings()
        }
        alertController.addAction(dismissAction)
        alertController.addAction(settingsAction)
        UIApplication.shared.frontmostViewController?.present(alertController, animated: true, completion: nil)
    }

    public class func showAlert(withTitle title: String) {
        self.showAlert(withTitle: title, message: nil, buttonTitle: nil)
    }

    public class func showAlert(withTitle title: String, message: String) {
        self.showAlert(withTitle: title, message: message, buttonTitle: nil)
    }

    public class func showAlert(withTitle title: String, message: String? = nil, buttonTitle: String? = nil) {
        assert(title.characters.count > 0)

        let actionTitle = buttonTitle ?? NSLocalizedString("OK", comment: "")

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: actionTitle, style: .default, handler: nil))
        UIApplication.shared.frontmostViewController?.present(alert, animated: true, completion: nil)
    }

    public class func showConfirmationAlert(withTitle title: String, message: String? = nil, proceedTitle: String? = nil, proceedAction: @escaping (UIAlertAction) -> Void) {
        assert(title.characters.count > 0)

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(self.cancelAction)

        let actionTitle = proceedTitle ?? NSLocalizedString("OK", comment: "")
        alert.addAction(UIAlertAction(title: actionTitle, style: .default, handler: proceedAction))

        UIApplication.shared.frontmostViewController?.present(alert, animated: true, completion: nil)
    }

    public class var cancelAction: UIAlertAction {
        let action = UIAlertAction(title: CommonStrings.cancelButton, style: .cancel) { _ in
            Logger.debug("Cancel item")
            // Do nothing.
        }
        return action
    }

}
