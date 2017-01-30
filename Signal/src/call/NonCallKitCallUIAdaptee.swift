//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

/**
 * Manage call related UI in a pre-CallKit world.
 */
class NonCallKitCallUIAdaptee: CallUIAdaptee {

    let TAG = "[NonCallKitCallUIAdaptee]"

    let notificationsAdapter: CallNotificationsAdapter
    let callService: CallService

    // Starting/Stopping incoming call ringing is our apps responsibility for the non CallKit interface.
    let hasManualRinger = true

    required init(callService: CallService, notificationsAdapter: CallNotificationsAdapter) {
        self.callService = callService
        self.notificationsAdapter = notificationsAdapter
    }

    func startOutgoingCall(handle: String) -> SignalCall {
        AssertIsOnMainThread()

        let call = SignalCall.outgoingCall(localId: UUID(), remotePhoneNumber: handle)

        CallService.signalingQueue.async {
            _ = self.callService.handleOutgoingCall(call).then {
                Logger.debug("\(self.TAG) handleOutgoingCall succeeded")
            }.catch { error in
                Logger.error("\(self.TAG) handleOutgoingCall failed with error: \(error)")
            }
        }

        return call
    }

    func reportIncomingCall(_ call: SignalCall, callerName: String) {
        AssertIsOnMainThread()

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

    func reportMissedCall(_ call: SignalCall, callerName: String) {
        AssertIsOnMainThread()

        notificationsAdapter.presentMissedCall(call, callerName: callerName)
    }

    func answerCall(localId: UUID) {
        AssertIsOnMainThread()

        CallService.signalingQueue.async {
            guard let call = self.callService.call else {
                assertionFailure("\(self.TAG) in \(#function) No current call.")
                return
            }

            guard call.localId == localId else {
                assertionFailure("\(self.TAG) in \(#function) localId does not match current call")
                return
            }

            self.answerCall(call)
        }
    }

    func answerCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        CallService.signalingQueue.async {
            guard call.localId == self.callService.call?.localId else {
                assertionFailure("\(self.TAG) in \(#function) localId does not match current call")
                return
            }

            PeerConnectionClient.startAudioSession()
            self.callService.handleAnswerCall(call)
        }
    }

    func declineCall(localId: UUID) {
        AssertIsOnMainThread()

        CallService.signalingQueue.async {
            guard let call = self.callService.call else {
                assertionFailure("\(self.TAG) in \(#function) No current call.")
                return
            }

            guard call.localId == localId else {
                assertionFailure("\(self.TAG) in \(#function) localId does not match current call")
                return
            }

            self.declineCall(call)
        }
    }

    func declineCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        CallService.signalingQueue.async {
            guard call.localId == self.callService.call?.localId else {
                assertionFailure("\(self.TAG) in \(#function) localId does not match current call")
                return
            }

            self.callService.handleDeclineCall(call)
        }
    }

    func recipientAcceptedCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        PeerConnectionClient.startAudioSession()
    }

    func localHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        CallService.signalingQueue.async {
            // If both parties hang up at the same moment,
            // call might already be nil.
            guard self.callService.call == nil || call.localId == self.callService.call?.localId else {
                assertionFailure("\(self.TAG) in \(#function) localId does not match current call")
                return
            }

            self.callService.handleLocalHungupCall(call)
        }
    }

    internal func remoteDidHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        Logger.debug("\(TAG) in \(#function) is no-op")
    }

    internal func failCall(_ call: SignalCall, error: CallError) {
        AssertIsOnMainThread()

        Logger.debug("\(TAG) in \(#function) is no-op")
    }

    func setIsMuted(call: SignalCall, isMuted: Bool) {
        AssertIsOnMainThread()

        CallService.signalingQueue.async {
            guard call.localId == self.callService.call?.localId else {
                assertionFailure("\(self.TAG) in \(#function) localId does not match current call")
                return
            }

            self.callService.setIsMuted(isMuted: isMuted)
        }
    }

    func setHasLocalVideo(call: SignalCall, hasLocalVideo: Bool) {
        AssertIsOnMainThread()

        CallService.signalingQueue.async {
            guard call.localId == self.callService.call?.localId else {
                assertionFailure("\(self.TAG) in \(#function) localId does not match current call")
                return
            }

            self.callService.setHasLocalVideo(hasLocalVideo: hasLocalVideo)
        }
    }
}
