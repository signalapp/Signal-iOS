//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Foundation
import CallKit
public import SignalServiceKit
import SignalUI
import WebRTC
import UIKit

protocol CallUIAdaptee: AnyObject {
    var callService: CallService { get }

    init(showNamesOnCallScreen: Bool, useSystemCallLog: Bool)

    @MainActor
    func startOutgoingCall(call: SignalCall)

    // TODO: It might be nice to prevent call links from being passed here at compile time.
    @MainActor
    func reportIncomingCall(_ call: SignalCall, completion: @escaping (Error?) -> Void)

    @MainActor
    func answerCall(_ call: SignalCall)

    @MainActor
    func recipientAcceptedCall(_ call: CallMode)

    @MainActor
    func localHangupCall(_ call: SignalCall)

    @MainActor
    func remoteDidHangupCall(_ call: SignalCall)

    @MainActor
    func remoteBusy(_ call: SignalCall)

    @MainActor
    func didAnswerElsewhere(call: SignalCall)

    @MainActor
    func didDeclineElsewhere(call: SignalCall)

    @MainActor
    func wasBusyElsewhere(call: SignalCall)

    @MainActor
    func failCall(_ call: SignalCall, error: CallError)

    @MainActor
    func setIsMuted(call: SignalCall, isMuted: Bool)

    @MainActor
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
        let (showNames, useSystemCallLog) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return (
                SSKEnvironment.shared.preferencesRef.notificationPreviewType(tx: tx) != .noNameNoPreview,
                SSKEnvironment.shared.preferencesRef.isSystemCallLogEnabled(tx: tx)
            )
        }
        return callUIAdapteeType.init(
            showNamesOnCallScreen: showNames,
            useSystemCallLog: useSystemCallLog
        )
    }()

    @MainActor
    public override init() {
        super.init()

        // We cannot assert singleton here, because this class gets rebuilt when the user changes relevant call settings
    }

    @MainActor
    internal func reportIncomingCall(_ call: SignalCall) {
        guard let caller = call.caller else {
            return
        }
        Logger.info("remoteAddress: \(caller)")

        // make sure we don't terminate audio session during call
        _ = SUIEnvironment.shared.audioSessionRef.startAudioActivity(call.commonState.audioActivity)

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

    @MainActor
    internal func reportMissedCall(_ call: SignalCall, individualCall: IndividualCall) {
        guard let callerAci = individualCall.thread.contactAddress.aci else {
            owsFailDebug("Can't receive a call without an ACI.")
            return
        }

        let sentAtTimestamp = Date(millisecondsSince1970: individualCall.sentAtTimestamp)
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            SSKEnvironment.shared.notificationPresenterRef.notifyUserOfMissedCall(
                notificationInfo: CallNotificationInfo(
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

    @MainActor
    internal func startOutgoingCall(call: SignalCall) {
        // make sure we don't terminate audio session during call
        _ = SUIEnvironment.shared.audioSessionRef.startAudioActivity(call.commonState.audioActivity)

        adaptee.startOutgoingCall(call: call)
    }

    @MainActor
    internal func answerCall(_ call: SignalCall) {
        adaptee.answerCall(call)
    }

    @MainActor
    public func startAndShowOutgoingCall(thread: TSContactThread, hasLocalVideo: Bool) {
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

        startOutgoingCall(call: call)
        individualCall.hasLocalVideo = hasLocalVideo
        self.showCall(call)
    }

    @MainActor
    internal func recipientAcceptedCall(_ call: CallMode) {
        adaptee.recipientAcceptedCall(call)
    }

    @MainActor
    internal func remoteDidHangupCall(_ call: SignalCall) {
        adaptee.remoteDidHangupCall(call)
    }

    @MainActor
    internal func remoteBusy(_ call: SignalCall) {
        adaptee.remoteBusy(call)
    }

    @MainActor
    internal func didAnswerElsewhere(call: SignalCall) {
        adaptee.didAnswerElsewhere(call: call)
    }

    @MainActor
    internal func didDeclineElsewhere(call: SignalCall) {
        adaptee.didDeclineElsewhere(call: call)
    }

    @MainActor
    internal func wasBusyElsewhere(call: SignalCall) {
        adaptee.wasBusyElsewhere(call: call)
    }

    @MainActor
    internal func localHangupCall(_ call: SignalCall) {
        adaptee.localHangupCall(call)
    }

    @MainActor
    internal func failCall(_ call: SignalCall, error: CallError) {
        adaptee.failCall(call, error: error)
    }

    @MainActor
    private func showCall(_ call: SignalCall) {
        guard !call.hasTerminated else {
            Logger.info("Not showing window for terminated call \(call)")
            return
        }

        Logger.info("\(call)")

        let callViewController: UIViewController & CallViewControllerWindowReference
        switch call.mode {
        case .individual(let individualCall):
            callViewController = IndividualCallViewController(call: call, individualCall: individualCall)
        case .groupThread(let groupCall as GroupCall), .callLink(let groupCall as GroupCall):
            callViewController = SSKEnvironment.shared.databaseStorageRef.read { tx in
                return GroupCallViewController.load(call: call, groupCall: groupCall, tx: tx)
            }
        }

        callViewController.modalTransitionStyle = .crossDissolve
        AppEnvironment.shared.windowManagerRef.startCall(viewController: callViewController)
    }

    @MainActor
    internal func setIsMuted(call: SignalCall, isMuted: Bool) {
        // With CallKit, muting is handled by a CXAction, so it must go through the adaptee
        adaptee.setIsMuted(call: call, isMuted: isMuted)
    }

    @MainActor
    internal func setHasLocalVideo(call: SignalCall, hasLocalVideo: Bool) {
        adaptee.setHasLocalVideo(call: call, hasLocalVideo: hasLocalVideo)
    }

    @MainActor
    internal func setCameraSource(call: SignalCall, isUsingFrontCamera: Bool) {
        callService.updateCameraSource(call: call, isUsingFrontCamera: isUsingFrontCamera)
    }
}
