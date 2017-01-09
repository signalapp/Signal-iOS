//  Created by Michael Kirk on 1/3/17.
//  Copyright © 2017 Open Whisper Systems. All rights reserved.

import Foundation

/**
 * Manage call related UI in a pre-CallKit world.
 */
class NonCallKitCallUIAdaptee: CallUIAdaptee {

    let TAG = "[NonCallKitCallUIAdaptee]"

    let notificationsAdapter: CallNotificationsAdapter
    let callService: CallService

    required init(callService: CallService, notificationsAdapter: CallNotificationsAdapter) {
        self.callService = callService
        self.notificationsAdapter = notificationsAdapter
    }

    internal func startOutgoingCall(_ call: SignalCall) {
        CallService.signalingQueue.async {
            _ = self.callService.handleOutgoingCall(call).then {
                Logger.debug("\(self.TAG) handleOutgoingCall succeeded")
            }.catch { error in
                Logger.error("\(self.TAG) handleOutgoingCall failed with error: \(error)")
            }
        }
    }

    internal func reportIncomingCall(_ call: SignalCall, callerName: String) {
        Logger.debug("\(TAG) \(#function)")

        // present Call View controller
        let callNotificationName = CallService.callServiceActiveCallNotificationName()
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: callNotificationName), object: call)

        // present lock screen notification
        if UIApplication.shared.applicationState == .active {
            Logger.debug("\(TAG) skipping notification since app is already active.")
        } else {
            notificationsAdapter.presentIncomingCall(call, callerName: callerName)
        }
    }

    internal func reportMissedCall(_ call: SignalCall, callerName: String) {
        notificationsAdapter.presentMissedCall(call, callerName: callerName)
    }

    internal func answerCall(_ call: SignalCall) {
        // NO-OP
    }

    internal func declineCall(_ call: SignalCall) {
        CallService.signalingQueue.async {
            self.callService.handleDeclineCall(call)
        }
    }

    internal func endCall(_ call: SignalCall) {
        CallService.signalingQueue.async {
            self.callService.handleLocalHungupCall(call)
        }
    }

    internal func toggleMute(call: SignalCall, isMuted: Bool) {
        CallService.signalingQueue.async {
            self.callService.handleToggledMute(isMuted: isMuted)
        }
    }

}
