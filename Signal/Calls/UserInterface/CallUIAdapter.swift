//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import CallKit
import SignalServiceKit
import WebRTC
import UIKit

protocol CallUIAdaptee: AnyObject {
    var notificationPresenterImpl: NotificationPresenterImpl { get }
    var callService: CallService { get }

    init(showNamesOnCallScreen: Bool, useSystemCallLog: Bool)

    func startOutgoingCall(call: SignalCall)
    func reportIncomingCall(_ call: SignalCall, completion: @escaping (Error?) -> Void)
    func answerCall(_ call: SignalCall)
    func recipientAcceptedCall(_ call: CallMode)
    func localHangupCall(_ call: SignalCall)
    func remoteDidHangupCall(_ call: SignalCall)
    func remoteBusy(_ call: SignalCall)
    func didAnswerElsewhere(call: SignalCall)
    func didDeclineElsewhere(call: SignalCall)
    func wasBusyElsewhere(call: SignalCall)
    func failCall(_ call: SignalCall, error: CallError)
    func setIsMuted(call: SignalCall, isMuted: Bool)
    func setHasLocalVideo(call: SignalCall, hasLocalVideo: Bool)
}

/**
 * Notify the user of call related activities.
 * Driven by either a CallKit or System notifications adaptee
 */
public class CallUIAdapter: NSObject {

    private var callService: CallService { AppEnvironment.shared.callService }

    private lazy var adaptee: any CallUIAdaptee = { () -> any CallUIAdaptee in
        let callUIAdapteeType: CallUIAdaptee.Type
#if targetEnvironment(simulator)
        callUIAdapteeType = SimulatorCallUIAdaptee.self
#else
        callUIAdapteeType = CallKitCallUIAdaptee.self
#endif
        let (showNames, useSystemCallLog) = databaseStorage.read { tx in
            return (
                preferences.notificationPreviewType(tx: tx) != .noNameNoPreview,
                preferences.isSystemCallLogEnabled(tx: tx)
            )
        }
        return callUIAdapteeType.init(
            showNamesOnCallScreen: showNames,
            useSystemCallLog: useSystemCallLog
        )
    }()

    public override init() {
        AssertIsOnMainThread()

        super.init()

        // We cannot assert singleton here, because this class gets rebuilt when the user changes relevant call settings
    }

    // MARK: 

    internal func reportIncomingCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        guard let caller = call.caller else {
            return
        }
        Logger.info("remoteAddress: \(caller)")

        // make sure we don't terminate audio session during call
        _ = audioSession.startAudioActivity(call.commonState.audioActivity)

        adaptee.reportIncomingCall(call) { error in
            AssertIsOnMainThread()

            guard var error = error else {
                self.showCall(call)
                return
            }

            Logger.warn("error: \(error)")

            switch error {
            case CXErrorCodeIncomingCallError.filteredByDoNotDisturb:
                error = CallError.doNotDisturbEnabled
            case CXErrorCodeIncomingCallError.filteredByBlockList:
                error = CallError.contactIsBlocked
            default:
                break
            }

            self.callService.handleFailedCall(failedCall: call, error: error)
        }
    }

    internal func reportMissedCall(_ call: SignalCall, individualCall: IndividualCall) {
        AssertIsOnMainThread()

        guard let callerAci = individualCall.thread.contactAddress.aci else {
            owsFailDebug("Can't receive a call without an ACI.")
            return
        }

        let sentAtTimestamp = Date(millisecondsSince1970: individualCall.sentAtTimestamp)
        databaseStorage.read { tx in
            notificationPresenterImpl.presentMissedCall(
                notificationInfo: NotificationPresenterImpl.CallNotificationInfo(
                    groupingId: individualCall.commonState.localId,
                    thread: individualCall.thread,
                    caller: callerAci
                ),
                offerMediaType: individualCall.offerMediaType,
                sentAt: sentAtTimestamp,
                tx: tx
            )
        }
    }

    internal func startOutgoingCall(call: SignalCall) {
        AssertIsOnMainThread()

        // make sure we don't terminate audio session during call
        _ = audioSession.startAudioActivity(call.commonState.audioActivity)

        adaptee.startOutgoingCall(call: call)
    }

    internal func answerCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        adaptee.answerCall(call)
    }

    public func startAndShowOutgoingCall(thread: TSContactThread, hasLocalVideo: Bool) {
        AssertIsOnMainThread()

        guard let (call, individualCall) = self.callService.buildOutgoingIndividualCallIfPossible(
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
        individualCall.hasLocalVideo = hasLocalVideo
        self.showCall(call)
    }

    internal func recipientAcceptedCall(_ call: CallMode) {
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

    internal func didAnswerElsewhere(call: SignalCall) {
        adaptee.didAnswerElsewhere(call: call)
    }

    internal func didDeclineElsewhere(call: SignalCall) {
        adaptee.didDeclineElsewhere(call: call)
    }

    internal func wasBusyElsewhere(call: SignalCall) {
        adaptee.wasBusyElsewhere(call: call)
    }

    internal func localHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        adaptee.localHangupCall(call)
    }

    internal func failCall(_ call: SignalCall, error: CallError) {
        AssertIsOnMainThread()

        adaptee.failCall(call, error: error)
    }

    private func showCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        guard !call.hasTerminated else {
            Logger.info("Not showing window for terminated call \(call)")
            return
        }

        Logger.info("\(call)")

        let callViewController: UIViewController & CallViewControllerWindowReference
        switch call.mode {
        case .individual(let individualCall):
            callViewController = IndividualCallViewController(call: call, individualCall: individualCall)
        case .groupThread(let groupThreadCall):
            callViewController = GroupCallViewController(call: call, groupThreadCall: groupThreadCall)
        }

        callViewController.modalTransitionStyle = .crossDissolve
        WindowManager.shared.startCall(viewController: callViewController)
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

    internal func setCameraSource(call: SignalCall, isUsingFrontCamera: Bool) {
        AssertIsOnMainThread()

        callService.updateCameraSource(call: call, isUsingFrontCamera: isUsingFrontCamera)
    }
}
