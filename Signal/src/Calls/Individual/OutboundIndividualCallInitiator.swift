//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

/**
 * Creates an outbound call via WebRTC.
 */
@objc
public class OutboundIndividualCallInitiator: NSObject {

    @objc
    public override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    /**
     * |address| is a SignalServiceAddress.
     */
    @discardableResult
    @objc
    public func initiateCall(thread: TSContactThread, isVideo: Bool) -> Bool {
        guard tsAccountManager.isOnboarded() else {
            Logger.warn("aborting due to user not being onboarded.")
            OWSActionSheets.showActionSheet(title: NSLocalizedString("YOU_MUST_COMPLETE_ONBOARDING_BEFORE_PROCEEDING",
                                                                     comment: "alert body shown when trying to use features in the app before completing registration-related setup."))
            return false
        }

        guard let callUIAdapter = Self.callService.callUIAdapter else {
            owsFailDebug("missing callUIAdapter")
            return false
        }
        guard let frontmostViewController = UIApplication.shared.frontmostViewController else {
            owsFailDebug("could not identify frontmostViewController")
            return false
        }

        let showedAlert = SafetyNumberConfirmationSheet.presentIfNecessary(
            address: thread.contactAddress,
            confirmationText: CallStrings.confirmAndCallButtonTitle
        ) { didConfirmIdentity in
            guard didConfirmIdentity else { return }
            _ = self.initiateCall(thread: thread, isVideo: isVideo)
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

                    callUIAdapter.startAndShowOutgoingCall(thread: thread, hasLocalVideo: true)
                }
            } else {
                callUIAdapter.startAndShowOutgoingCall(thread: thread, hasLocalVideo: false)
            }
        }

        return true
    }
}
