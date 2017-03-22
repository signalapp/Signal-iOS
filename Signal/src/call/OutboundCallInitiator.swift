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
    public func initiateCall(handle: String) {
        Logger.info("\(TAG) in \(#function) with handle: \(handle)")

        guard let recipientId = PhoneNumber(fromUserSpecifiedText: handle)?.toE164() else {
            Logger.warn("\(TAG) unable to parse signalId from phone number: \(handle)")
            return
        }

        initiateCall(recipientId: recipientId)
    }

    /**
     * |recipientId| is a e164 formatted phone number.
     */
    public func initiateCall(recipientId: String) {
        self.initiateWebRTCAudioCall(recipientId: recipientId)
    }

    private func initiateWebRTCAudioCall(recipientId: String) {
        // Rather than an init-assigned dependency property, we access `callUIAdapter` via Environment 
        // because it can change after app launch due to user settings
        guard let callUIAdapter = Environment.getCurrent().callUIAdapter else {
            assertionFailure()
            Logger.error("\(TAG) can't initiate call because callUIAdapter is nil")
            return
        }

        callUIAdapter.startAndShowOutgoingCall(recipientId: recipientId)
    }
}
