//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

/**
 * Creates an outbound call via WebRTC.
 */
@objc public class OutboundIndividualCallInitiator: NSObject {

    @objc public override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    /**
     * |address| is a SignalServiceAddress
     */
    @discardableResult
    @objc
    public func initiateCall(publicKey: String) -> Bool {
        return initiateCall(publicKey: publicKey, isVideo: false)
    }

    /**
     * |address| is a SignalServiceAddress.
     */
    @discardableResult
    @objc
    public func initiateCall(publicKey: String, isVideo: Bool) -> Bool {
        guard let callUIAdapter = Self.callService.individualCallService.callUIAdapter else {
            owsFailDebug("missing callUIAdapter")
            return false
        }
        guard let frontmostViewController = UIApplication.shared.frontmostViewController else {
            owsFailDebug("could not identify frontmostViewController")
            return false
        }

        frontmostViewController.ows_ask(forMicrophonePermissions: { granted in
            guard granted == true else {
                Logger.warn("aborting due to missing microphone permissions.")
                frontmostViewController.ows_showNoMicrophonePermissionActionSheet()
                return
            }

            if isVideo {
                frontmostViewController.ows_ask(forCameraPermissions: { granted in
                    guard granted else {
                        Logger.warn("aborting due to missing camera permissions.")
                        return
                    }

                    callUIAdapter.startAndShowOutgoingCall(publicKey: publicKey, hasLocalVideo: true)
                })
            } else {
                callUIAdapter.startAndShowOutgoingCall(publicKey: publicKey, hasLocalVideo: false)
            }
        })

        return true
    }
}
