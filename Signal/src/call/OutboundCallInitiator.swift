//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

/**
 * Creates an outbound call via either Redphone or WebRTC depending on participant preferences.
 */
@objc class OutboundCallInitiator: NSObject {
    let TAG = "[OutboundCallInitiator]"

    let redphoneManager: PhoneManager
    let contactsManager: OWSContactsManager
    let contactsUpdater: ContactsUpdater

    var cancelledCallTokens: [String] = []

    init(redphoneManager: PhoneManager, contactsManager: OWSContactsManager, contactsUpdater: ContactsUpdater) {
        self.redphoneManager = redphoneManager

        self.contactsManager = contactsManager
        self.contactsUpdater = contactsUpdater

        super.init()

        NotificationCenter.default.addObserver(self,
                                               selector:#selector(callWasCancelledByInterstitial),
                                               name:Notification.Name(rawValue: CallService.callWasCancelledByInterstitialNotificationName()),
                                               object:nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func callWasCancelledByInterstitial(notification: NSNotification) {
        AssertIsOnMainThread()

        let callToken = notification.object as! String
        cancelCallToken(callToken:callToken)
    }

    func cancelCallToken(callToken: String) {
        AssertIsOnMainThread()

        cancelledCallTokens.append(callToken)
    }

    /**
     * |handle| is a user formatted phone number, e.g. from a system contacts entry
     */
    public func initiateCall(handle: String) -> Bool {
        Logger.info("\(TAG) in \(#function) with handle: \(handle)")
        guard let recipientId = PhoneNumber(fromUserSpecifiedText: handle).toE164() else {
            Logger.warn("\(TAG) unable to parse signalId from phone number: \(handle)")
            return false
        }

        return initiateCall(recipientId: recipientId)
    }

    /**
     * |recipientId| is a e164 formatted phone number.
     */
    public func initiateCall(recipientId: String) -> Bool {

        let localWantsWebRTC = Environment.preferences().isWebRTCEnabled()
        if !localWantsWebRTC {
            return self.initiateRedphoneCall(recipientId: recipientId)
        }

        // A temporary unique id used to identify this call during the 
        let callToken = NSUUID().uuidString
        presentCallInterstitial(callToken:callToken)

        // Since users can toggle this setting, which is only communicated during contact sync, it's easy to imagine the
        // preference getting stale. Especially as users are toggling the feature to test calls. So here, we opt for a
        // blocking network request *every* time we place a call to make sure we've got up to date preferences.
        //
        // e.g. The following would suffice if we weren't worried about stale preferences.
        // SignalRecipient *recipient = [SignalRecipient recipientWithTextSecureIdentifier:self.thread.contactIdentifier];
        self.contactsUpdater.lookupIdentifier(recipientId,
                                              success: { recipient in
                                                guard !self.cancelledCallTokens.contains(callToken) else {
                                                    Logger.info("\(self.TAG) OutboundCallInitiator aborting due to cancelled call.")
                                                    return
                                                }

                                                guard !Environment.getCurrent().phoneManager.hasOngoingRedphoneCall() else {
                                                    Logger.error("\(self.TAG) OutboundCallInitiator aborting due to ongoing RedPhone call.")
                                                    return
                                                }
                                                guard Environment.getCurrent().callService.call == nil else {
                                                    Logger.error("\(self.TAG) OutboundCallInitiator aborting due to ongoing WebRTC call.")
                                                    return
                                                }

                                                let remoteWantsWebRTC = recipient.supportsWebRTC
                                                Logger.debug("\(self.TAG) localWantsWebRTC: \(localWantsWebRTC), remoteWantsWebRTC: \(remoteWantsWebRTC)")

                                                if localWantsWebRTC, remoteWantsWebRTC {
                                                    _ = self.initiateWebRTCAudioCall(recipientId: recipientId)
                                                } else {
                                                    _ = self.initiateRedphoneCall(recipientId: recipientId)
                                                }
        },
                                              failure: { error in
                                                Logger.warn("\(self.TAG) looking up recipientId: \(recipientId) failed with error \(error)")

                                                self.cancelCallToken(callToken:callToken)
                                                self.dismissCallInterstitial(callToken:callToken)

                                                let alertTitle = NSLocalizedString("UNABLE_TO_PLACE_CALL", comment:"Alert Title")
                                                let alertController = UIAlertController(title: alertTitle, message: error.localizedDescription, preferredStyle: .alert)

                                                let dismissAction = UIAlertAction(title: NSLocalizedString("DISMISS_BUTTON_TEXT", comment: "Generic short text for button to dismiss a dialog"), style: .default)
                                                alertController.addAction(dismissAction)
                                                UIApplication.shared.keyWindow?.rootViewController?.present(alertController, animated: true, completion: nil)
        })

        // Since we've already dispatched async to make sure we have fresh webrtc preference data
        // we don't have a meaningful value to return here - but we're not using it anway. =/
        return true
    }

    private func initiateRedphoneCall(recipientId: String) -> Bool {
        Logger.info("\(TAG) Placing redphone call to: \(recipientId)")

        let number = PhoneNumber.tryParsePhoneNumber(fromUserSpecifiedText: recipientId)
        assert(number != nil)

        let contact: Contact? = self.contactsManager.latestContact(for: number)

        redphoneManager.initiateOutgoingCall(to: contact, atRemoteNumber: number)

        return true
    }

    private func initiateWebRTCAudioCall(recipientId: String) -> Bool {
        // Rather than an init-assigned dependency property, we access `callUIAdapter` via Environment 
        // because it can change after app launch due to user settings
        guard let callUIAdapter = Environment.getCurrent().callUIAdapter else {
            assertionFailure()
            Logger.error("\(TAG) can't initiate call because callUIAdapter is nil")
            return false
        }

        callUIAdapter.startAndShowOutgoingCall(recipientId: recipientId)
        return true
    }

    private func presentCallInterstitial(callToken: String) {
        AssertIsOnMainThread()

        let notificationName = CallService.presentCallInterstitialNotificationName()
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: notificationName), object: callToken)
    }

    private func dismissCallInterstitial(callToken: String) {
        AssertIsOnMainThread()

        let notificationName = CallService.dismissCallInterstitialNotificationName()
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: notificationName), object: callToken)
    }
}
