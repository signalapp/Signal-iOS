//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

/**
 * Creates an outbound call via WebRTC.
 */
@objc class OutboundCallInitiator: NSObject {
    let TAG = "[OutboundCallInitiator]"

    let contactsManager: OWSContactsManager
    let contactsUpdater: ContactsUpdater

    init(contactsManager: OWSContactsManager, contactsUpdater: ContactsUpdater) {
        self.contactsManager = contactsManager
        self.contactsUpdater = contactsUpdater

        super.init()
    }

    /**
     * |handle| is a user formatted phone number, e.g. from a system contacts entry
     */
    public func initiateCall(handle: String) -> Bool {
        Logger.info("\(TAG) in \(#function) with handle: \(handle)")

        guard let recipientId = PhoneNumber(fromUserSpecifiedText: handle)?.toE164() else {
            Logger.warn("\(TAG) unable to parse signalId from phone number: \(handle)")
            return false
        }

        return initiateCall(recipientId: recipientId)
    }

    /**
     * |recipientId| is a e164 formatted phone number.
     */
    public func initiateCall(recipientId: String) -> Bool {
        // Rather than an init-assigned dependency property, we access `callUIAdapter` via Environment
        // because it can change after app launch due to user settings
        guard let callUIAdapter = Environment.getCurrent().callUIAdapter else {
            assertionFailure()
            Logger.error("\(TAG) can't initiate call because callUIAdapter is nil")
            return false
        }

        // Check for microphone permissions
        // Alternative way without prompting for permissions:
        // if AVAudioSession.sharedInstance().recordPermission() == .denied {
        AVAudioSession.sharedInstance().requestRecordPermission { isGranted in
            DispatchQueue.main.async {
                // Here the permissions are either granted or denied
                guard isGranted == true else {
                    Logger.warn("\(self.TAG) aborting due to missing microphone permissions.")
                    self.showNoMicrophonePermissionAlert()
                    return
                }
                callUIAdapter.startAndShowOutgoingCall(recipientId: recipientId)
            }
        }
        return true
    }

    /// Cleanup and present alert for no permissions
    private func showNoMicrophonePermissionAlert() {
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
}
