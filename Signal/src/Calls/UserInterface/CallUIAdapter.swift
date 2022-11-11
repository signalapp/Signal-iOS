//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import CallKit
import SignalServiceKit
import SignalMessaging
import WebRTC
import UIKit

protocol CallUIAdaptee: AnyObject {
    var notificationPresenter: NotificationPresenter { get }
    var callService: CallService { get }
    var hasManualRinger: Bool { get }

    func startOutgoingCall(call: SignalCall)
    func reportIncomingCall(_ call: SignalCall, completion: @escaping (Error?) -> Void)
    func reportMissedCall(_ call: SignalCall)
    func answerCall(localId: UUID)
    func answerCall(_ call: SignalCall)
    func recipientAcceptedCall(_ call: SignalCall)
    func localHangupCall(localId: UUID)
    func localHangupCall(_ call: SignalCall)
    func remoteDidHangupCall(_ call: SignalCall)
    func remoteBusy(_ call: SignalCall)
    func didAnswerElsewhere(call: SignalCall)
    func didDeclineElsewhere(call: SignalCall)
    func wasBusyElsewhere(call: SignalCall)
    func failCall(_ call: SignalCall, error: SignalCall.CallError)
    func setIsMuted(call: SignalCall, isMuted: Bool)
    func setHasLocalVideo(call: SignalCall, hasLocalVideo: Bool)
    func startAndShowOutgoingCall(thread: TSContactThread, hasLocalVideo: Bool)
}

// Shared default implementations
extension CallUIAdaptee {

    internal func showCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        guard !call.isTerminatedIndividualCall else {
            Logger.info("Not showing window for terminated individual call")
            return
        }

        Logger.info("showCall")

        let callViewController: UIViewController & CallViewControllerWindowReference
        if call.isGroupCall {
            callViewController = GroupCallViewController(call: call)
        } else {
            callViewController = IndividualCallViewController(call: call)
        }

        callViewController.modalTransitionStyle = .crossDissolve
        OWSWindowManager.shared.startCall(callViewController)
    }

    internal func reportMissedCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        let sentAtTimestamp = Date(millisecondsSince1970: call.individualCall.sentAtTimestamp)
        notificationPresenter.presentMissedCall(call,
                                                caller: call.individualCall.remoteAddress,
                                                sentAt: sentAtTimestamp)
    }

    internal func startAndShowOutgoingCall(thread: TSContactThread, hasLocalVideo: Bool) {
        AssertIsOnMainThread()

        guard let call = self.callService.buildOutgoingIndividualCallIfPossible(
            thread: thread,
            hasVideo: hasLocalVideo
        ) else {
            // @integration This is not unexpected, it could happen if Bob tries
            // to start an outgoing call at the same moment Alice has already
            // sent him an Offer that is being processed.
            Logger.info("found an existing call when trying to start outgoing call: \(thread.contactAddress)")
            return
        }

        Logger.debug("")

        startOutgoingCall(call: call)
        call.individualCall.hasLocalVideo = hasLocalVideo
        self.showCall(call)
    }
}

/**
 * Notify the user of call related activities.
 * Driven by either a CallKit or System notifications adaptee
 */
@objc
public class CallUIAdapter: NSObject, CallServiceObserver {

    lazy var nonCallKitAdaptee = NonCallKitCallUIAdaptee()

    lazy var callKitAdaptee: CallKitCallUIAdaptee? = {
        if Platform.isSimulator {
            // CallKit doesn't seem entirely supported in simulator.
            // e.g. you can't receive calls in the call screen.
            // So we use the non-CallKit call UI.
            Logger.info("not using callkit adaptee for simulator.")
            return nil
        } else if CallUIAdapter.isCallkitDisabledForLocale {
            Logger.info("not using callkit adaptee due to locale.")
            return nil
        } else {
            Logger.info("using callkit adaptee for iOS11+")
            let showNames = preferences.notificationPreviewType() != .noNameNoPreview
            let useSystemCallLog = preferences.isSystemCallLogEnabled()

            return CallKitCallUIAdaptee(showNamesOnCallScreen: showNames,
                                        useSystemCallLog: useSystemCallLog)
        }
    }()

    var defaultAdaptee: CallUIAdaptee { callKitAdaptee ?? nonCallKitAdaptee }

    func adaptee(for call: SignalCall) -> CallUIAdaptee {
        guard call.isIndividualCall else {
            return defaultAdaptee
        }
        switch call.individualCall.callAdapterType {
        case .nonCallKit: return nonCallKitAdaptee
        case .default: return defaultAdaptee
        }
    }

    public required override init() {
        AssertIsOnMainThread()

        super.init()

        // We cannot assert singleton here, because this class gets rebuilt when the user changes relevant call settings
        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            self.callService.addObserverAndSyncState(observer: self)
        }
    }

    @objc
    public static var isCallkitDisabledForLocale: Bool {
        let locale = Locale.current
        guard let regionCode = locale.regionCode else {
            if !Platform.isSimulator { owsFailDebug("Missing region code.") }
            return false
        }

        // Apple has stopped approving apps that use CallKit functionality in mainland China.
        // When the "CN" region is enabled, this check simply switches to the same pre-CallKit
        // interface that is still used by everyone on iOS 9.
        //
        // For further reference: https://forums.developer.apple.com/thread/103083
        return regionCode == "CN"
    }

    // MARK: 

    internal func reportIncomingCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        guard let caller = call.caller else {
            return
        }
        Logger.info("remoteAddress: \(caller)")

        // make sure we don't terminate audio session during call
        _ = audioSession.startAudioActivity(call.audioActivity)

        adaptee(for: call).reportIncomingCall(call) { error in
            AssertIsOnMainThread()

            guard var error = error else {
                // Individual calls ring on their state transitions, but group calls ring immediately.
                if call.isGroupCall {
                    // Wait to start ringing until all observers have recognized this as the current call.
                    DispatchQueue.main.async {
                        guard call == self.callService.currentCall else {
                            // Assume that the call failed before we got a chance to start ringing.
                            return
                        }
                        self.callService.audioService.startRinging(call: call)
                    }
                }
                return
            }

            let nsError: NSError = error as NSError
            Logger.warn("Error: \(nsError.domain), \(nsError.code), error: \(error)")
            if nsError.domain == CXErrorCodeIncomingCallError.errorDomain {
                switch nsError.code {
                case CXErrorCodeIncomingCallError.unknown.rawValue:
                    Logger.warn("unknown")
                case CXErrorCodeIncomingCallError.unentitled.rawValue:
                    Logger.warn("unentitled")
                case CXErrorCodeIncomingCallError.callUUIDAlreadyExists.rawValue:
                    Logger.warn("callUUIDAlreadyExists")
                case CXErrorCodeIncomingCallError.filteredByDoNotDisturb.rawValue:
                    Logger.warn("filteredByDoNotDisturb")
                    error = SignalCall.CallError.doNotDisturbEnabled
                case CXErrorCodeIncomingCallError.filteredByBlockList.rawValue:
                    Logger.warn("filteredByBlockList")
                    error = SignalCall.CallError.contactIsBlocked
                default:
                    Logger.warn("Unknown CXErrorCodeIncomingCallError")
                }
            }

            self.callService.handleFailedCall(failedCall: call, error: error)
        }
    }

    internal func reportMissedCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        adaptee(for: call).reportMissedCall(call)
    }

    internal func startOutgoingCall(call: SignalCall) {
        AssertIsOnMainThread()

        adaptee(for: call).startOutgoingCall(call: call)
    }

    @objc
    public func answerCall(localId: UUID) {
        AssertIsOnMainThread()

        guard let call = self.callService.currentCall else {
            owsFailDebug("No current call.")
            return
        }

        guard call.localId == localId else {
            owsFailDebug("localId does not match current call")
            return
        }

        adaptee(for: call).answerCall(localId: localId)
    }

    internal func answerCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        adaptee(for: call).answerCall(call)
    }

    @objc
    public func startAndShowOutgoingCall(thread: TSContactThread, hasLocalVideo: Bool) {
        AssertIsOnMainThread()

        defaultAdaptee.startAndShowOutgoingCall(thread: thread, hasLocalVideo: hasLocalVideo)
    }

    internal func recipientAcceptedCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        adaptee(for: call).recipientAcceptedCall(call)
    }

    internal func remoteDidHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        adaptee(for: call).remoteDidHangupCall(call)
    }

    internal func remoteBusy(_ call: SignalCall) {
        AssertIsOnMainThread()

        adaptee(for: call).remoteBusy(call)
    }

    internal func didAnswerElsewhere(call: SignalCall) {
        adaptee(for: call).didAnswerElsewhere(call: call)
    }

    internal func didDeclineElsewhere(call: SignalCall) {
        adaptee(for: call).didDeclineElsewhere(call: call)
    }

    internal func wasBusyElsewhere(call: SignalCall) {
        adaptee(for: call).wasBusyElsewhere(call: call)
    }

    internal func localHangupCall(localId: UUID) {
        AssertIsOnMainThread()

        guard let call = self.callService.currentCall else {
            owsFailDebug("No current call.")
            return
        }

        guard call.localId == localId else {
            owsFailDebug("localId does not match current call")
            return
        }

        adaptee(for: call).localHangupCall(localId: localId)
    }

    internal func localHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        adaptee(for: call).localHangupCall(call)
    }

    internal func failCall(_ call: SignalCall, error: SignalCall.CallError) {
        AssertIsOnMainThread()

        adaptee(for: call).failCall(call, error: error)
    }

    private func showCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        adaptee(for: call).showCall(call)
    }

    internal func setIsMuted(call: SignalCall, isMuted: Bool) {
        AssertIsOnMainThread()

        // With CallKit, muting is handled by a CXAction, so it must go through the adaptee
        adaptee(for: call).setIsMuted(call: call, isMuted: isMuted)
    }

    internal func setHasLocalVideo(call: SignalCall, hasLocalVideo: Bool) {
        AssertIsOnMainThread()

        adaptee(for: call).setHasLocalVideo(call: call, hasLocalVideo: hasLocalVideo)
    }

    internal func setCameraSource(call: SignalCall, isUsingFrontCamera: Bool) {
        AssertIsOnMainThread()

        callService.updateCameraSource(call: call, isUsingFrontCamera: isUsingFrontCamera)
    }

    // MARK: - CallServiceObserver

    internal func didUpdateCall(from oldValue: SignalCall?, to newValue: SignalCall?) {
        AssertIsOnMainThread()

        guard let call = newValue else { return }

        callService.audioService.handleRinging = adaptee(for: call).hasManualRinger
    }
}
