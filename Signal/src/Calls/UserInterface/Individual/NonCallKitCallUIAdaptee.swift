//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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

        self.callService.individualCallService.handleOutgoingCall(call)
    }

    func reportIncomingCall(_ call: SignalCall, callerName: String, completion: @escaping (Error?) -> Void) {
        AssertIsOnMainThread()

        Logger.debug("")

        self.showCall(call)

        startNotifiyingForIncomingCall(call, callerName: callerName)

        completion(nil)
    }

    private var incomingCallNotificationTimer: Timer?
    private func startNotifiyingForIncomingCall(_ call: SignalCall, callerName: String) {
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
                self?.notificationPresenter.presentIncomingCall(call.individualCall, callerName: callerName)
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

        self.callService.individualCallService.handleLocalHangupCall(call)
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
