//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import CallKit
import SignalServiceKit
import SignalMessaging
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
    func startAndShowOutgoingCall(recipientId: String, hasLocalVideo: Bool)
}

// Shared default implementations
extension CallUIAdaptee {
    internal func showCall(_ call: SignalCall) {
        SwiftAssertIsOnMainThread(#function)

        let callViewController = CallViewController(call: call)
        callViewController.modalTransitionStyle = .crossDissolve

        if CallViewController.kShowCallViewOnSeparateWindow {
            OWSWindowManager.shared().startCall(callViewController)
        } else {
            guard let presentingViewController = UIApplication.shared.frontmostViewControllerIgnoringAlerts else {
                owsFail("in \(#function) view controller unexpectedly nil")
                return
            }

            if let presentedViewController = presentingViewController.presentedViewController {
                presentedViewController.dismiss(animated: false) {
                    presentingViewController.present(callViewController, animated: true)
                }
            } else {
                presentingViewController.present(callViewController, animated: true)
            }
        }
    }

    internal func reportMissedCall(_ call: SignalCall, callerName: String) {
        SwiftAssertIsOnMainThread(#function)

        notificationsAdapter.presentMissedCall(call, callerName: callerName)
    }

    internal func startAndShowOutgoingCall(recipientId: String, hasLocalVideo: Bool) {
        SwiftAssertIsOnMainThread(#function)

        guard self.callService.call == nil else {
            owsFail("unexpectedly found an existing call when trying to start outgoing call: \(recipientId)")
            self.callService.terminateCallDueToCriticalError()
            return
        }

        let call = self.startOutgoingCall(handle: recipientId)
        call.hasLocalVideo = hasLocalVideo
        self.showCall(call)
    }
}

/**
 * Notify the user of call related activities.
 * Driven by either a CallKit or System notifications adaptee
 */
@objc public class CallUIAdapter: NSObject, CallServiceObserver {

    let TAG = "[CallUIAdapter]"
    private let adaptee: CallUIAdaptee
    private let contactsManager: OWSContactsManager
    internal let audioService: CallAudioService
    internal let callService: CallService

    public required init(callService: CallService, contactsManager: OWSContactsManager, notificationsAdapter: CallNotificationsAdapter) {
        SwiftAssertIsOnMainThread(#function)

        self.contactsManager = contactsManager
        self.callService = callService

        if Platform.isSimulator {
            // CallKit doesn't seem entirely supported in simulator.
            // e.g. you can't receive calls in the call screen.
            // So we use the non-CallKit call UI.
            Logger.info("\(TAG) choosing non-callkit adaptee for simulator.")
            adaptee = NonCallKitCallUIAdaptee(callService: callService, notificationsAdapter: notificationsAdapter)
        } else if #available(iOS 11, *) {
            Logger.info("\(TAG) choosing callkit adaptee for iOS11+")
            let showNames = Environment.preferences().notificationPreviewType() != .noNameNoPreview
            let useSystemCallLog = Environment.preferences().isSystemCallLogEnabled()

            adaptee = CallKitCallUIAdaptee(callService: callService, contactsManager: contactsManager, notificationsAdapter: notificationsAdapter, showNamesOnCallScreen: showNames, useSystemCallLog: useSystemCallLog)
        } else if #available(iOS 10.0, *), Environment.current().preferences.isCallKitEnabled() {
            Logger.info("\(TAG) choosing callkit adaptee for iOS10")
            let hideNames = Environment.preferences().isCallKitPrivacyEnabled() || Environment.preferences().notificationPreviewType() == .noNameNoPreview
            let showNames = !hideNames

            // All CallKit calls use the system call log on iOS10
            let useSystemCallLog = true

            adaptee = CallKitCallUIAdaptee(callService: callService, contactsManager: contactsManager, notificationsAdapter: notificationsAdapter, showNamesOnCallScreen: showNames, useSystemCallLog: useSystemCallLog)
        } else {
            Logger.info("\(TAG) choosing non-callkit adaptee")
            adaptee = NonCallKitCallUIAdaptee(callService: callService, notificationsAdapter: notificationsAdapter)
        }

        audioService = CallAudioService(handleRinging: adaptee.hasManualRinger)

        super.init()

        // We cannot assert singleton here, because this class gets rebuilt when the user changes relevant call settings

        callService.addObserverAndSyncState(observer: self)
    }

    internal func reportIncomingCall(_ call: SignalCall, thread: TSContactThread) {
        SwiftAssertIsOnMainThread(#function)

        // make sure we don't terminate audio session during call
        OWSAudioSession.shared.startAudioActivity(call.audioActivity)

        let callerName = self.contactsManager.displayName(forPhoneIdentifier: call.remotePhoneNumber)
        adaptee.reportIncomingCall(call, callerName: callerName)
    }

    internal func reportMissedCall(_ call: SignalCall) {
        SwiftAssertIsOnMainThread(#function)

        let callerName = self.contactsManager.displayName(forPhoneIdentifier: call.remotePhoneNumber)
        adaptee.reportMissedCall(call, callerName: callerName)
    }

    internal func startOutgoingCall(handle: String) -> SignalCall {
        SwiftAssertIsOnMainThread(#function)

        let call = adaptee.startOutgoingCall(handle: handle)
        return call
    }

    @objc public func answerCall(localId: UUID) {
        SwiftAssertIsOnMainThread(#function)

        adaptee.answerCall(localId: localId)
    }

    internal func answerCall(_ call: SignalCall) {
        SwiftAssertIsOnMainThread(#function)

        adaptee.answerCall(call)
    }

    @objc public func declineCall(localId: UUID) {
        SwiftAssertIsOnMainThread(#function)

        adaptee.declineCall(localId: localId)
    }

    internal func declineCall(_ call: SignalCall) {
        SwiftAssertIsOnMainThread(#function)

        adaptee.declineCall(call)
    }

    internal func didTerminateCall(_ call: SignalCall?) {
        SwiftAssertIsOnMainThread(#function)

        if let call = call {
            OWSAudioSession.shared.endAudioActivity(call.audioActivity)
        }
    }

    @objc public func startAndShowOutgoingCall(recipientId: String, hasLocalVideo: Bool) {
        SwiftAssertIsOnMainThread(#function)

        adaptee.startAndShowOutgoingCall(recipientId: recipientId, hasLocalVideo: hasLocalVideo)
    }

    internal func recipientAcceptedCall(_ call: SignalCall) {
        SwiftAssertIsOnMainThread(#function)

        adaptee.recipientAcceptedCall(call)
    }

    internal func remoteDidHangupCall(_ call: SignalCall) {
        SwiftAssertIsOnMainThread(#function)

        adaptee.remoteDidHangupCall(call)
    }

    internal func remoteBusy(_ call: SignalCall) {
        SwiftAssertIsOnMainThread(#function)

        adaptee.remoteBusy(call)
    }

    internal func localHangupCall(_ call: SignalCall) {
        SwiftAssertIsOnMainThread(#function)

        adaptee.localHangupCall(call)
    }

    internal func failCall(_ call: SignalCall, error: CallError) {
        SwiftAssertIsOnMainThread(#function)

        adaptee.failCall(call, error: error)
    }

    internal func showCall(_ call: SignalCall) {
        SwiftAssertIsOnMainThread(#function)

        adaptee.showCall(call)
    }

    internal func setIsMuted(call: SignalCall, isMuted: Bool) {
        SwiftAssertIsOnMainThread(#function)

        // With CallKit, muting is handled by a CXAction, so it must go through the adaptee
        adaptee.setIsMuted(call: call, isMuted: isMuted)
    }

    internal func setHasLocalVideo(call: SignalCall, hasLocalVideo: Bool) {
        SwiftAssertIsOnMainThread(#function)

        adaptee.setHasLocalVideo(call: call, hasLocalVideo: hasLocalVideo)
    }

    internal func setAudioSource(call: SignalCall, audioSource: AudioSource?) {
        SwiftAssertIsOnMainThread(#function)

        // AudioSource is not handled by CallKit (e.g. there is no CXAction), so we handle it w/o going through the
        // adaptee, relying on the AudioService CallObserver to put the system in a state consistent with the call's
        // assigned property.
        call.audioSource = audioSource
    }

    internal func setCameraSource(call: SignalCall, useBackCamera: Bool) {
        SwiftAssertIsOnMainThread(#function)

        callService.setCameraSource(call: call, useBackCamera: useBackCamera)
    }

    // CallKit handles ringing state on it's own. But for non-call kit we trigger ringing start/stop manually.
    internal var hasManualRinger: Bool {
        SwiftAssertIsOnMainThread(#function)

        return adaptee.hasManualRinger
    }

    // MARK: - CallServiceObserver

    internal func didUpdateCall(call: SignalCall?) {
        SwiftAssertIsOnMainThread(#function)

        call?.addObserverAndSyncState(observer: audioService)
    }

    internal func didUpdateVideoTracks(call: SignalCall?,
                                       localVideoTrack: RTCVideoTrack?,
                                       remoteVideoTrack: RTCVideoTrack?) {
        SwiftAssertIsOnMainThread(#function)

        audioService.didUpdateVideoTracks(call: call)
    }
}
