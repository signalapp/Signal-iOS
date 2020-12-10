//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import CallKit
import SignalServiceKit
import SignalMessaging
import WebRTC

protocol CallUIAdaptee {
    var notificationPresenter: NotificationPresenter { get }
    var hasManualRinger: Bool { get }

    func startOutgoingCall(call: SignalCall)
    func reportIncomingCall(_ call: SignalCall, callerName: String, completion: @escaping (Error?) -> Void)
    func reportMissedCall(_ call: SignalCall, callerName: String)
    func answerCall(localId: UUID)
    func answerCall(_ call: SignalCall)
    func recipientAcceptedCall(_ call: SignalCall)
    func localHangupCall(localId: UUID)
    func localHangupCall(_ call: SignalCall)
    func remoteDidHangupCall(_ call: SignalCall)
    func remoteBusy(_ call: SignalCall)
    func didAnswerElsewhere(call: SignalCall)
    func didDeclineElsewhere(call: SignalCall)
    func failCall(_ call: SignalCall, error: SignalCall.CallError)
    func setIsMuted(call: SignalCall, isMuted: Bool)
    func setHasLocalVideo(call: SignalCall, hasLocalVideo: Bool)
    func startAndShowOutgoingCall(address: SignalServiceAddress, hasLocalVideo: Bool)
}

// Shared default implementations
extension CallUIAdaptee {
    var callService: CallService {
        return AppEnvironment.shared.callService
    }

    internal func showCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        let callViewController = IndividualCallViewController(call: call)
        callViewController.modalTransitionStyle = .crossDissolve

        OWSWindowManager.shared.startCall(callViewController)
    }

    internal func reportMissedCall(_ call: SignalCall, callerName: String) {
        AssertIsOnMainThread()

        notificationPresenter.presentMissedCall(call.individualCall, callerName: callerName)
    }

    internal func startAndShowOutgoingCall(address: SignalServiceAddress, hasLocalVideo: Bool) {
        AssertIsOnMainThread()

        guard let call = self.callService.buildOutgoingIndividualCallIfPossible(
            address: address,
            hasVideo: hasLocalVideo
        ) else {
            // @integration This is not unexpected, it could happen if Bob tries
            // to start an outgoing call at the same moment Alice has already
            // sent him an Offer that is being processed.
            Logger.info("found an existing call when trying to start outgoing call: \(address)")
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
@objc public class CallUIAdapter: NSObject, CallServiceObserver {

    var contactsManager: OWSContactsManager { Environment.shared.contactsManager }
    var callService: CallService { AppEnvironment.shared.callService }

    private var notificationPresenter: NotificationPresenter {
        return AppEnvironment.shared.notificationPresenter
    }

    var preferences: OWSPreferences {
        return Environment.shared.preferences
    }

    lazy var nonCallKitAdaptee = NonCallKitCallUIAdaptee(
        notificationPresenter: notificationPresenter
    )

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
        switch call.individualCall.callAdapterType {
        case .nonCallKit: return nonCallKitAdaptee
        case .default: return defaultAdaptee
        }
    }

    public required override init() {
        AssertIsOnMainThread()

        super.init()

        // We cannot assert singleton here, because this class gets rebuilt when the user changes relevant call settings
        AppReadiness.runNowOrWhenAppDidBecomeReady {
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

    // MARK: Dependencies

    var audioSession: OWSAudioSession {
        return Environment.shared.audioSession
    }

    // MARK: 

    internal func reportIncomingCall(_ call: SignalCall, thread: TSContactThread) {
        AssertIsOnMainThread()

        Logger.info("remoteAddress: \(call.individualCall.remoteAddress)")

        // make sure we don't terminate audio session during call
        _ = audioSession.startAudioActivity(call.audioActivity)

        let callerName = self.contactsManager.displayName(for: call.individualCall.remoteAddress)

        Logger.verbose("callerName: \(callerName)")

        adaptee(for: call).reportIncomingCall(call, callerName: callerName) { error in
            AssertIsOnMainThread()

            guard let error = error else { return }
            owsFailDebug("Failed to report incoming call with error \(error)")

            let nsError = error as NSError
            Logger.warn("nsError: \(nsError.domain), \(nsError.code)")
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
                case CXErrorCodeIncomingCallError.filteredByBlockList.rawValue:
                    Logger.warn("filteredByBlockList")
                default:
                    Logger.warn("Unknown CXErrorCodeIncomingCallError")
                }
            }

            self.callService.handleFailedCall(failedCall: call, error: error)
        }
    }

    internal func reportMissedCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        let callerName = self.contactsManager.displayName(for: call.individualCall.remoteAddress)
        adaptee(for: call).reportMissedCall(call, callerName: callerName)
    }

    internal func startOutgoingCall(call: SignalCall) {
        AssertIsOnMainThread()

        adaptee(for: call).startOutgoingCall(call: call)
    }

    @objc public func answerCall(localId: UUID) {
        AssertIsOnMainThread()

        guard let call = self.callService.currentCall else {
            owsFailDebug("No current call.")
            return
        }

        guard call.individualCall.localId == localId else {
            owsFailDebug("localId does not match current call")
            return
        }

        adaptee(for: call).answerCall(localId: localId)
    }

    internal func answerCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        adaptee(for: call).answerCall(call)
    }

    @objc public func startAndShowOutgoingCall(address: SignalServiceAddress, hasLocalVideo: Bool) {
        AssertIsOnMainThread()

        defaultAdaptee.startAndShowOutgoingCall(address: address, hasLocalVideo: hasLocalVideo)
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

    internal func localHangupCall(localId: UUID) {
        AssertIsOnMainThread()

        guard let call = self.callService.currentCall else {
            owsFailDebug("No current call.")
            return
        }

        guard call.individualCall.localId == localId else {
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

    internal func showCall(_ call: SignalCall) {
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

        guard let call = newValue, call.isIndividualCall else { return }

        callService.audioService.handleRinging = adaptee(for: call).hasManualRinger
    }
}
