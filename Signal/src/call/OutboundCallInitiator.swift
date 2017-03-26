//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

/**
 * Creates an outbound call via either Redphone or WebRTC depending on participant preferences.
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
        AVAudioSession.sharedInstance().requestRecordPermission { status in
            // Here the permissions are either granted or denied
            guard status == true else {
                Logger.warn("\(self.TAG) aborting due to missing microphone permissions.")
                self.showAlertNoPermission()
                return
            }
            callUIAdapter.startAndShowOutgoingCall(recipientId: recipientId)
        }
        return true
    }
    
    /// Cleanup and present alert for no permissions
    private func showAlertNoPermission() {
        let alertTitle = NSLocalizedString("CALL_AUDIO_PERMISSION_TITLE", comment:"Alert Title")
        let alertMessage = NSLocalizedString("CALL_AUDIO_PERMISSION_MESSAGE", comment:"Alert message")
        let alertController = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)
        let dismiss = NSLocalizedString("DISMISS_BUTTON_TEXT", comment: "Generic short text for button to dismiss a dialog")
        let dismissAction = UIAlertAction(title: dismiss, style: .default)
        alertController.addAction(dismissAction)
        UIApplication.shared.keyWindow?.rootViewController?.present(alertController, animated: true, completion: nil)
    }
}
