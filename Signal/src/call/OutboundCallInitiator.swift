//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

/**
 * Creates an outbound call via WebRTC.
 */
@objc public class OutboundCallInitiator: NSObject {

    @objc public override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    // MARK: - Dependencies

    private var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    private var contactsUpdater: ContactsUpdater {
        return SSKEnvironment.shared.contactsUpdater
    }

    // MARK: -

    /**
     * |handle| is a user formatted phone number, e.g. from a system contacts entry
     */
    @discardableResult
    @objc
    public func initiateCall(handle: String) -> Bool {
        Logger.info("with handle: \(handle)")

        guard let e164Number = PhoneNumber(fromE164: handle)?.toE164() else {
            Logger.warn("unable to parse signalId from phone number: \(handle)")
            return false
        }
        // TODO UUID: map phone number from contacts to UUID, maybe requires lookup?
        return initiateCall(address: e164Number.transitional_signalServiceAddress, isVideo: false)
    }

    /**
     * |recipientId| is a e164 formatted phone number.
     */
    @discardableResult
    @objc
    public func initiateCall(address: SignalServiceAddress, isVideo: Bool) -> Bool {
        guard let callUIAdapter = AppEnvironment.shared.callService.callUIAdapter else {
            owsFailDebug("missing callUIAdapter")
            return false
        }
        guard let frontmostViewController = UIApplication.shared.frontmostViewController else {
            owsFailDebug("could not identify frontmostViewController")
            return false
        }

        let showedAlert = SafetyNumberConfirmationAlert.presentAlertIfNecessary(address: address,
                                                                                confirmationText: CallStrings.confirmAndCallButtonTitle,
                                                                                contactsManager: self.contactsManager,
                                                                                completion: { didConfirmIdentity in
                                                                                    if didConfirmIdentity {
                                                                                        _ = self.initiateCall(address: address, isVideo: isVideo)
                                                                                    }
        })
        guard !showedAlert else {
            return false
        }

        frontmostViewController.ows_askForMicrophonePermissions { granted in
            guard granted == true else {
                Logger.warn("aborting due to missing microphone permissions.")
                OWSAlerts.showNoMicrophonePermissionAlert()
                return
            }
            callUIAdapter.startAndShowOutgoingCall(recipientId: address.transitional_phoneNumber, hasLocalVideo: isVideo)
        }

        return true
    }
}
