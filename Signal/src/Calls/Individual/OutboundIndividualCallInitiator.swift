//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

/**
 * Creates an outbound call via WebRTC.
 */
@objc public class OutboundIndividualCallInitiator: NSObject {

    @objc public override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    // MARK: - Dependencies

    private var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    private var tsAccountManager: TSAccountManager {
        return .shared()
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
        guard tsAccountManager.isOnboarded() else {
            Logger.warn("aborting due to user not being onboarded.")
            OWSActionSheets.showActionSheet(title: NSLocalizedString("YOU_MUST_COMPLETE_ONBOARDING_BEFORE_PROCEEDING",
                                                                     comment: "alert body shown when trying to use features in the app before completing registration-related setup."))
            return false
        }

        guard let callUIAdapter = AppEnvironment.shared.callService.individualCallService.callUIAdapter else {
            owsFailDebug("missing callUIAdapter")
            return false
        }
        guard let frontmostViewController = UIApplication.shared.frontmostViewController else {
            owsFailDebug("could not identify frontmostViewController")
            return false
        }

        let showedAlert = SafetyNumberConfirmationSheet.presentIfNecessary(
            address: address,
            confirmationText: CallStrings.confirmAndCallButtonTitle
        ) { didConfirmIdentity in
            guard didConfirmIdentity else { return }
            _ = self.initiateCall(address: address, isVideo: isVideo)
        }
        guard !showedAlert else {
            return false
        }

        frontmostViewController.ows_askForMicrophonePermissions { granted in
            guard granted == true else {
                Logger.warn("aborting due to missing microphone permissions.")
                frontmostViewController.ows_showNoMicrophonePermissionActionSheet()
                return
            }

            if isVideo {
                frontmostViewController.ows_askForCameraPermissions { granted in
                    guard granted else {
                        Logger.warn("aborting due to missing camera permissions.")
                        return
                    }

                    callUIAdapter.startAndShowOutgoingCall(address: address, hasLocalVideo: true)
                }
            } else {
                callUIAdapter.startAndShowOutgoingCall(address: address, hasLocalVideo: false)
            }
        }

        return true
    }
}
