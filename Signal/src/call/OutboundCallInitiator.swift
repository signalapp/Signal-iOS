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
     * |address| is a SignalServiceAddress
     */
    @discardableResult
    @objc
    public func initiateCall(address: SignalServiceAddress) -> Bool {
        Logger.info("with address: \(address)")

        guard address.isValid else { return false }

        return initiateCall(address: address, isVideo: false)
    }

    /**
     * |address| is a SignalServiceAddress.
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
            callUIAdapter.startAndShowOutgoingCall(address: address, hasLocalVideo: isVideo)
        }

        return true
    }
}
