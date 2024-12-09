//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalRingRTC
import SignalServiceKit
import SignalUI

protocol GroupCallObserver: AnyObject {

    @MainActor
    func groupCallLocalDeviceStateChanged(_ call: GroupCall)

    @MainActor
    func groupCallRemoteDeviceStatesChanged(_ call: GroupCall)

    @MainActor
    func groupCallPeekChanged(_ call: GroupCall)

    @MainActor
    func groupCallEnded(_ call: GroupCall, reason: GroupCallEndReason)
    func groupCallReceivedReactions(_ call: GroupCall, reactions: [SignalRingRTC.Reaction])
    func groupCallReceivedRaisedHands(_ call: GroupCall, raisedHands: [DemuxId])

    /// Invoked if a call message failed to send because of a safety number change
    /// UI observing call state may choose to alert the user (e.g. presenting a SafetyNumberConfirmationSheet)
    func handleUntrustedIdentityError(_ call: GroupCall)
}

extension GroupCallObserver {
    func groupCallLocalDeviceStateChanged(_ call: GroupCall) {}
    func groupCallRemoteDeviceStatesChanged(_ call: GroupCall) {}
    func groupCallPeekChanged(_ call: GroupCall) {}
    func groupCallEnded(_ call: GroupCall, reason: GroupCallEndReason) {}
    func groupCallReceivedReactions(_ call: GroupCall, reactions: [SignalRingRTC.Reaction]) {}
    func groupCallReceivedRaisedHands(_ call: GroupCall, raisedHands: [DemuxId]) {}
    func handleUntrustedIdentityError(_ call: GroupCall) {}
}

class GroupCall: SignalRingRTC.GroupCallDelegate {
    enum Constants {
        /// Automatically mute on join when seeing this many members in a call before we join.
        static let autoMuteThreshold = 8
    }

    let commonState: CommonCallState
    let ringRtcCall: SignalRingRTC.GroupCall
    private(set) var raisedHands: [DemuxId] = []
    let videoCaptureController: VideoCaptureController

    /// Tracks whether or not we've called connect().
    ///
    /// We can't use ringRtcCall.connectionState because it's updated asynchronously.
    var hasInvokedConnectMethod = false

    /// Tracks whether or not we should terminate the call when it ends.
    var shouldTerminateOnEndEvent = false

    init(
        audioDescription: String,
        ringRtcCall: SignalRingRTC.GroupCall,
        videoCaptureController: VideoCaptureController
    ) {
        self.commonState = CommonCallState(
            audioActivity: AudioActivity(audioDescription: audioDescription, behavior: .call)
        )
        self.ringRtcCall = ringRtcCall
        self.videoCaptureController = videoCaptureController
        self.ringRtcCall.delegate = self
    }

    var joinState: JoinState {
        return self.ringRtcCall.localDeviceState.joinState
    }

    var hasJoinedOrIsWaitingForAdminApproval: Bool {
        switch self.joinState {
        case .notJoined, .joining:
            return false
        case .joined, .pending:
            return true
        }
    }

    func shouldMuteAutomatically() -> Bool {
        return (
            ringRtcCall.localDeviceState.joinState == .notJoined
            && (ringRtcCall.peekInfo?.deviceCountExcludingPendingDevices ?? 0) >= Constants.autoMuteThreshold
        )
    }

    public var isJustMe: Bool {
        switch ringRtcCall.localDeviceState.joinState {
        case .notJoined, .joining, .pending:
            return true
        case .joined:
            return ringRtcCall.remoteDeviceStates.isEmpty
        }
    }

    // MARK: - Concrete Type

    enum ConcreteType {
        case groupThread(GroupThreadCall)
        case callLink(CallLinkCall)
    }

    var concreteType: ConcreteType {
        switch self {
        case let groupThreadCall as GroupThreadCall:
            return .groupThread(groupThreadCall)
        case let callLinkCall as CallLinkCall:
            return .callLink(callLinkCall)
        default:
            owsFail("Can't have any other type of call.")
        }
    }

    // MARK: - Observers

    private var observers: WeakArray<any GroupCallObserver> = []

    @MainActor
    func addObserver(_ observer: any GroupCallObserver, syncStateImmediately: Bool = false) {
        observers.append(observer)

        if syncStateImmediately {
            // Synchronize observer with current call state
            observer.groupCallLocalDeviceStateChanged(self)
            observer.groupCallRemoteDeviceStatesChanged(self)
        }
    }

    func removeObserver(_ observer: any GroupCallObserver) {
        observers.removeAll(where: { $0 === observer })
    }

    func handleUntrustedIdentityError() {
        observers.elements.forEach { $0.handleUntrustedIdentityError(self) }
    }

    // MARK: - GroupCallDelegate

    @MainActor
    func groupCall(onLocalDeviceStateChanged groupCall: SignalRingRTC.GroupCall) {
        if groupCall.localDeviceState.joinState == .joined, commonState.setConnectedDateIfNeeded() {
            // make sure we don't terminate audio session during call
            SUIEnvironment.shared.audioSessionRef.isRTCAudioEnabled = true
            owsAssertDebug(SUIEnvironment.shared.audioSessionRef.startAudioActivity(commonState.audioActivity))
        }

        observers.elements.forEach { $0.groupCallLocalDeviceStateChanged(self) }
    }

    @MainActor
    private var groupCallRemoteDeviceStatesChangedObserverTask: Task<Void, Never>?
    @MainActor
    func groupCall(onRemoteDeviceStatesChanged groupCall: SignalRingRTC.GroupCall) {
        // Debounce this event 0.25s to avoid spamming the calls UI with group changes.
        groupCallRemoteDeviceStatesChangedObserverTask?.cancel()
        groupCallRemoteDeviceStatesChangedObserverTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch is CancellationError {
                return
            } catch {
                owsFailDebug("unexpected error: \(error)")
                return
            }

            guard let self else { return }

            for element in observers.elements {
                element.groupCallRemoteDeviceStatesChanged(self)
            }
            groupCallRemoteDeviceStatesChangedObserverTask = nil
        }
    }

    func groupCall(onAudioLevels groupCall: SignalRingRTC.GroupCall) {
        // TODO: Implement audio level handling for group calls.
    }

    func groupCall(onLowBandwidthForVideo groupCall: SignalRingRTC.GroupCall, recovered: Bool) {
        // TODO: Implement handling of the "low outgoing bandwidth for video" notification.
    }

    func groupCall(onReactions groupCall: SignalRingRTC.GroupCall, reactions: [SignalRingRTC.Reaction]) {
        observers.elements.forEach { $0.groupCallReceivedReactions(self, reactions: reactions) }
    }

    func groupCall(onRaisedHands groupCall: SignalRingRTC.GroupCall, raisedHands: [DemuxId]) {
        self.raisedHands = raisedHands

        observers.elements.forEach {
            $0.groupCallReceivedRaisedHands(self, raisedHands: raisedHands)
        }
    }

    @MainActor
    func groupCall(onPeekChanged groupCall: SignalRingRTC.GroupCall) {
        observers.elements.forEach { $0.groupCallPeekChanged(self) }
    }

    func groupCall(requestMembershipProof groupCall: SignalRingRTC.GroupCall) {
    }

    func groupCall(requestGroupMembers groupCall: SignalRingRTC.GroupCall) {
    }

    @MainActor
    func groupCall(onEnded groupCall: SignalRingRTC.GroupCall, reason: GroupCallEndReason) {
        self.hasInvokedConnectMethod = false

        observers.elements.forEach { $0.groupCallEnded(self, reason: reason) }
    }

    @MainActor
    func groupCall(onSpeakingNotification groupCall: SignalRingRTC.GroupCall, event: SpeechEvent) {

    }
}
