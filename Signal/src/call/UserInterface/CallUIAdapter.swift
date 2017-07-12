//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import CallKit
import WebRTC

protocol CallUIAdaptee {
    var notificationsAdapter: CallNotificationsAdapter { get }
    var callService: CallService { get }
    var hasManualRinger: Bool { get }

    func startOutgoingCall(handle: String) -> SignalCall
    func reportIncomingCall(_ call: SignalCall, callerName: String)
    func reportMissedCall(_ call: SignalCall, callerName: String)
    func answerCall(localId: UUID)
    func answerCall(_ call: SignalCall)
    func declineCall(localId: UUID)
    func declineCall(_ call: SignalCall)
    func recipientAcceptedCall(_ call: SignalCall)
    func localHangupCall(_ call: SignalCall)
    func remoteDidHangupCall(_ call: SignalCall)
    func remoteBusy(_ call: SignalCall)
    func failCall(_ call: SignalCall, error: CallError)
    func setIsMuted(call: SignalCall, isMuted: Bool)
    func setHasLocalVideo(call: SignalCall, hasLocalVideo: Bool)
    func startAndShowOutgoingCall(recipientId: String)
}

// Shared default implementations
extension CallUIAdaptee {
    internal func showCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        let callViewController = CallViewController()
        let thread = TSContactThread.getOrCreateThread(contactId: call.remotePhoneNumber)
        callViewController.call = call
        callViewController.thread = thread
        callViewController.modalTransitionStyle = .crossDissolve

        guard let presentingViewController = Environment.getCurrent().signalsViewController else {
            owsFail("in \(#function) view controller unexpectedly nil")
            return
        }

        if let presentedViewController = presentingViewController.presentedViewController {
            presentedViewController.dismiss(animated: false)
        }
        presentingViewController.present(callViewController, animated: true)
    }

    internal func reportMissedCall(_ call: SignalCall, callerName: String) {
        AssertIsOnMainThread()

        notificationsAdapter.presentMissedCall(call, callerName: callerName)
    }

    internal func startAndShowOutgoingCall(recipientId: String) {
        AssertIsOnMainThread()

        guard self.callService.call == nil else {
            Logger.info("unexpectedly found an existing call when trying to start outgoing call: \(recipientId)")
            //TODO terminate existing call.
            return
        }

        let call = self.startOutgoingCall(handle: recipientId)
        self.showCall(call)
    }
}

/**
 * Notify the user of call related activities.
 * Driven by either a CallKit or System notifications adaptee
 */
@objc class CallUIAdapter: NSObject, CallServiceObserver {

    let TAG = "[CallUIAdapter]"
    private let adaptee: CallUIAdaptee
    private let contactsManager: OWSContactsManager
    internal let audioService: CallAudioService

    required init(callService: CallService, contactsManager: OWSContactsManager, notificationsAdapter: CallNotificationsAdapter) {
        AssertIsOnMainThread()

        self.contactsManager = contactsManager
        if Platform.isSimulator {
            // CallKit doesn't seem entirely supported in simulator.
            // e.g. you can't receive calls in the call screen.
            // So we use the non-CallKit call UI.
            Logger.info("\(TAG) choosing non-callkit adaptee for simulator.")
            adaptee = NonCallKitCallUIAdaptee(callService: callService, notificationsAdapter: notificationsAdapter)
        } else if #available(iOS 10.0, *), Environment.getCurrent().preferences.isCallKitEnabled() {
            Logger.info("\(TAG) choosing callkit adaptee for iOS10+")
            adaptee = CallKitCallUIAdaptee(callService: callService, notificationsAdapter: notificationsAdapter)
        } else {
            Logger.info("\(TAG) choosing non-callkit adaptee")
            adaptee = NonCallKitCallUIAdaptee(callService: callService, notificationsAdapter: notificationsAdapter)
        }

        audioService = CallAudioService(handleRinging: adaptee.hasManualRinger)

        super.init()

        callService.addObserverAndSyncState(observer: self)
    }

    internal func reportIncomingCall(_ call: SignalCall, thread: TSContactThread) {
        AssertIsOnMainThread()

        let callerName = self.contactsManager.displayName(forPhoneIdentifier: call.remotePhoneNumber)
        adaptee.reportIncomingCall(call, callerName: callerName)
    }

    internal func reportMissedCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        let callerName = self.contactsManager.displayName(forPhoneIdentifier: call.remotePhoneNumber)
        adaptee.reportMissedCall(call, callerName: callerName)
    }

    internal func startOutgoingCall(handle: String) -> SignalCall {
        AssertIsOnMainThread()

        let call = adaptee.startOutgoingCall(handle: handle)
        return call
    }

    internal func answerCall(localId: UUID) {
        AssertIsOnMainThread()

        adaptee.answerCall(localId: localId)
    }

    internal func answerCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        adaptee.answerCall(call)
    }

    internal func declineCall(localId: UUID) {
        AssertIsOnMainThread()

        adaptee.declineCall(localId: localId)
    }

    internal func declineCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        adaptee.declineCall(call)
    }

    internal func startAndShowOutgoingCall(recipientId: String) {
        AssertIsOnMainThread()

        adaptee.startAndShowOutgoingCall(recipientId: recipientId)
    }

    internal func recipientAcceptedCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        adaptee.recipientAcceptedCall(call)
    }

    internal func remoteDidHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        adaptee.remoteDidHangupCall(call)
    }

    internal func remoteBusy(_ call: SignalCall) {
        AssertIsOnMainThread()

        adaptee.remoteBusy(call)
    }

    internal func localHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        adaptee.localHangupCall(call)
    }

    internal func failCall(_ call: SignalCall, error: CallError) {
        AssertIsOnMainThread()

        adaptee.failCall(call, error: error)
    }

    internal func showCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        adaptee.showCall(call)
    }

    internal func setIsMuted(call: SignalCall, isMuted: Bool) {
        AssertIsOnMainThread()

        // With CallKit, muting is handled by a CXAction, so it must go through the adaptee
        adaptee.setIsMuted(call: call, isMuted: isMuted)
    }

    internal func setHasLocalVideo(call: SignalCall, hasLocalVideo: Bool) {
        AssertIsOnMainThread()

        adaptee.setHasLocalVideo(call: call, hasLocalVideo: hasLocalVideo)
    }

    internal func setIsSpeakerphoneEnabled(call: SignalCall, isEnabled: Bool) {
        AssertIsOnMainThread()

        // Speakerphone is not handled by CallKit (e.g. there is no CXAction), so we handle it w/o going through the
        // adaptee, relying on the AudioService CallObserver to put the system in a state consistent with the call's 
        // assigned property.
        call.isSpeakerphoneEnabled = isEnabled
    }

    // CallKit handles ringing state on it's own. But for non-call kit we trigger ringing start/stop manually.
    internal var hasManualRinger: Bool {
        AssertIsOnMainThread()

        return adaptee.hasManualRinger
    }

    // MARK: - CallServiceObserver

    internal func didUpdateCall(call: SignalCall?) {
        AssertIsOnMainThread()

        call?.addObserverAndSyncState(observer: audioService)
    }

    internal func didUpdateVideoTracks(call: SignalCall?,
                                       localVideoTrack: RTCVideoTrack?,
                                       remoteVideoTrack: RTCVideoTrack?) {
        AssertIsOnMainThread()

        audioService.didUpdateVideoTracks(call:call)
    }
}
