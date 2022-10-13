//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalMessaging

/**
 * Manage call related UI in a pre-CallKit world.
 */
class NonCallKitCallUIAdaptee: NSObject, CallUIAdaptee {

    // Starting/Stopping incoming call ringing is our apps responsibility for the non CallKit interface.
    let hasManualRinger = true

    required override init() {
        AssertIsOnMainThread()

        super.init()
    }

    // MARK: 

    func startOutgoingCall(call: SignalCall) {
        AssertIsOnMainThread()

        // make sure we don't terminate audio session during call
        let success = self.audioSession.startAudioActivity(call.audioActivity)
        assert(success)

        if call.isIndividualCall {
            self.callService.individualCallService.handleOutgoingCall(call)
        } else {
            switch call.groupCallRingState {
            case .shouldRing, .ringing:
                // Let CallService call recipientAcceptedCall when someone joins.
                break
            case .ringingEnded:
                owsFailDebug("ringing ended while we were starting the call")
                fallthrough
            case .doNotRing:
                // Immediately consider ourselves connected.
                recipientAcceptedCall(call)
            }
        }
    }

    func reportIncomingCall(_ call: SignalCall, completion: @escaping (Error?) -> Void) {
        AssertIsOnMainThread()

        Logger.debug("")

        self.showCall(call)

        startNotifiyingForIncomingCall(call, caller: call.individualCall.remoteAddress)

        completion(nil)
    }

    private var incomingCallNotificationTimer: Timer?
    private func startNotifiyingForIncomingCall(_ call: SignalCall, caller: SignalServiceAddress) {
        incomingCallNotificationTimer?.invalidate()
        incomingCallNotificationTimer = nil

        // present lock screen notification if we're in the background.
        // we re-present the notifiation every 3 seconds to make sure
        // the user sees that their phone is ringing
        incomingCallNotificationTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard call.individualCall.state == .localRinging_ReadyToAnswer else {
                self?.incomingCallNotificationTimer?.invalidate()
                self?.incomingCallNotificationTimer = nil
                return
            }
            if UIApplication.shared.applicationState == .active {
                Logger.debug("skipping notification since app is already active.")
            } else {
                self?.notificationPresenter.presentIncomingCall(call, caller: caller)
            }
        }
    }

    func answerCall(localId: UUID) {
        AssertIsOnMainThread()

        guard let call = self.callService.currentCall else {
            owsFailDebug("No current call.")
            return
        }

        guard call.localId == localId else {
            owsFailDebug("localId does not match current call")
            return
        }

        self.answerCall(call)
    }

    func answerCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        guard call.localId == self.callService.currentCall?.localId else {
            owsFailDebug("localId does not match current call")
            return
        }

        self.callService.individualCallService.handleAcceptCall(call)

        // Enable audio for locally accepted calls after the session is configured.
        self.audioSession.isRTCAudioEnabled = true
    }

    func recipientAcceptedCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        // Enable audio for remotely accepted calls after the session is configured.
        self.audioSession.isRTCAudioEnabled = true
    }

    func localHangupCall(localId: UUID) {
        AssertIsOnMainThread()

        guard let call = self.callService.currentCall else {
            owsFailDebug("No current call.")
            return
        }

        guard call.localId == localId else {
            owsFailDebug("localId does not match current call")
            return
        }

        self.localHangupCall(call)
    }

    func localHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        // If both parties hang up at the same moment,
        // call might already be nil.
        guard self.callService.currentCall == nil || call.localId == self.callService.currentCall?.localId else {
            owsFailDebug("localId does not match current call")
            return
        }

        callService.handleLocalHangupCall(call)
    }

    internal func remoteDidHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        Logger.debug("is no-op")
    }

    internal func remoteBusy(_ call: SignalCall) {
        AssertIsOnMainThread()

        Logger.debug("is no-op")
    }

    internal func didAnswerElsewhere(call: SignalCall) {
        AssertIsOnMainThread()

        Logger.debug("is no-op")
    }

    internal func didDeclineElsewhere(call: SignalCall) {
        AssertIsOnMainThread()

        Logger.debug("is no-op")
    }

    internal func wasBusyElsewhere(call: SignalCall) {
        AssertIsOnMainThread()

        Logger.debug("is no-op")
    }

    internal func failCall(_ call: SignalCall, error: SignalCall.CallError) {
        AssertIsOnMainThread()

        Logger.debug("is no-op")
    }

    func setIsMuted(call: SignalCall, isMuted: Bool) {
        AssertIsOnMainThread()

        guard call.localId == self.callService.currentCall?.localId else {
            owsFailDebug("localId does not match current call")
            return
        }

        self.callService.updateIsLocalAudioMuted(isLocalAudioMuted: isMuted)
    }

    func setHasLocalVideo(call: SignalCall, hasLocalVideo: Bool) {
        AssertIsOnMainThread()

        guard call.localId == self.callService.currentCall?.localId else {
            owsFailDebug("localId does not match current call")
            return
        }

        self.callService.updateIsLocalVideoMuted(isLocalVideoMuted: !hasLocalVideo)
    }
}
