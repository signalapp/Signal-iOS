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
        let dismiss = NSLocalizedString("DISMISS_BUTTON_TEXT", comment: "Generic short text for button to dismiss a dialog")
        let dismissAction = UIAlertAction(title: dismiss, style: .cancel)
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

        let actionTitle = (buttonTitle != nil ? buttonTitle : NSLocalizedString("OK", comment: ""))

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: actionTitle, style: .default, handler: nil))
        UIApplication.shared.frontmostViewController?.present(alert, animated: true, completion: nil)
    }
}
