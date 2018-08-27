//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

/**
 * Manage call related UI in a pre-CallKit world.
 */
class NonCallKitCallUIAdaptee: NSObject, CallUIAdaptee {

    let notificationsAdapter: CallNotificationsAdapter
    let callService: CallService

    // Starting/Stopping incoming call ringing is our apps responsibility for the non CallKit interface.
    let hasManualRinger = true

    required init(callService: CallService, notificationsAdapter: CallNotificationsAdapter) {
        AssertIsOnMainThread()

        self.callService = callService
        self.notificationsAdapter = notificationsAdapter

        super.init()
    }

    func startOutgoingCall(handle: String) -> SignalCall {
        AssertIsOnMainThread()

        let call = SignalCall.outgoingCall(localId: UUID(), remotePhoneNumber: handle)

        // make sure we don't terminate audio session during call
        OWSAudioSession.shared.startAudioActivity(call.audioActivity)

        self.callService.handleOutgoingCall(call).then {
            Logger.debug("handleOutgoingCall succeeded")
        }.catch { error in
            Logger.error("handleOutgoingCall failed with error: \(error)")
        }.retainUntilComplete()

        return call
    }

    func reportIncomingCall(_ call: SignalCall, callerName: String) {
        AssertIsOnMainThread()

        Logger.debug("")

        self.showCall(call)

        // present lock screen notification
        if UIApplication.shared.applicationState == .active {
            Logger.debug("skipping notification since app is already active.")
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

        guard let call = self.callService.call else {
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

        guard call.localId == self.callService.call?.localId else {
            owsFailDebug("localId does not match current call")
            return
        }

        OWSAudioSession.shared.isRTCAudioEnabled = true
        self.callService.handleAnswerCall(call)
    }

    func declineCall(localId: UUID) {
        AssertIsOnMainThread()

        guard let call = self.callService.call else {
            owsFailDebug("No current call.")
            return
        }

        guard call.localId == localId else {
            owsFailDebug("localId does not match current call")
            return
        }

        self.declineCall(call)
    }

    func declineCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        guard call.localId == self.callService.call?.localId else {
            owsFailDebug("localId does not match current call")
            return
        }

        self.callService.handleDeclineCall(call)
    }

    func recipientAcceptedCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        OWSAudioSession.shared.isRTCAudioEnabled = true
    }

    func localHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        // If both parties hang up at the same moment,
        // call might already be nil.
        guard self.callService.call == nil || call.localId == self.callService.call?.localId else {
            owsFailDebug("localId does not match current call")
            return
        }

        self.callService.handleLocalHungupCall(call)
    }

    internal func remoteDidHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        Logger.debug("is no-op")
    }

    internal func remoteBusy(_ call: SignalCall) {
        AssertIsOnMainThread()

        Logger.debug("is no-op")
    }

    internal func failCall(_ call: SignalCall, error: CallError) {
        AssertIsOnMainThread()

        Logger.debug("is no-op")
    }

    func setIsMuted(call: SignalCall, isMuted: Bool) {
        AssertIsOnMainThread()

        guard call.localId == self.callService.call?.localId else {
            owsFailDebug("localId does not match current call")
            return
        }

        self.callService.setIsMuted(call: call, isMuted: isMuted)
    }

    func setHasLocalVideo(call: SignalCall, hasLocalVideo: Bool) {
        AssertIsOnMainThread()

        guard call.localId == self.callService.call?.localId else {
            owsFailDebug("localId does not match current call")
            return
        }

        self.callService.setHasLocalVideo(hasLocalVideo: hasLocalVideo)
    }
}
