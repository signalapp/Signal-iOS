//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalRingRTC
import SignalServiceKit
import SignalUI

protocol GroupThreadCallObserver: AnyObject {
    func groupCallLocalDeviceStateChanged(_ call: GroupThreadCall)
    func groupCallRemoteDeviceStatesChanged(_ call: GroupThreadCall)
    func groupCallPeekChanged(_ call: GroupThreadCall)
    func groupCallRequestMembershipProof(_ call: GroupThreadCall)
    func groupCallRequestGroupMembers(_ call: GroupThreadCall)
    func groupCallEnded(_ call: GroupThreadCall, reason: GroupCallEndReason)
    func groupCallReceivedReactions(_ call: GroupThreadCall, reactions: [SignalRingRTC.Reaction])
    func groupCallReceivedRaisedHands(_ call: GroupThreadCall, raisedHands: [UInt32])

    /// Invoked if a call message failed to send because of a safety number change
    /// UI observing call state may choose to alert the user (e.g. presenting a SafetyNumberConfirmationSheet)
    func callMessageSendFailedUntrustedIdentity(_ call: GroupThreadCall)
}

extension GroupThreadCallObserver {
    func groupCallLocalDeviceStateChanged(_ call: GroupThreadCall) {}
    func groupCallRemoteDeviceStatesChanged(_ call: GroupThreadCall) {}
    func groupCallPeekChanged(_ call: GroupThreadCall) {}
    func groupCallRequestMembershipProof(_ call: GroupThreadCall) {}
    func groupCallRequestGroupMembers(_ call: GroupThreadCall) {}
    func groupCallEnded(_ call: GroupThreadCall, reason: GroupCallEndReason) {}
    func groupCallReceivedReactions(_ call: GroupThreadCall, reactions: [SignalRingRTC.Reaction]) {}
    func groupCallReceivedRaisedHands(_ call: GroupThreadCall, raisedHands: [UInt32]) {}
    func callMessageSendFailedUntrustedIdentity(_ call: GroupThreadCall) {}
}

class GroupThreadCall {
    let commonState: CommonCallState
    let ringRtcCall: SignalRingRTC.GroupCall
    let groupThread: TSGroupThread
    let videoCaptureController: VideoCaptureController

    private(set) var raisedHands: [RemoteDeviceState] = []

    init(
        ringRtcCall: SignalRingRTC.GroupCall,
        groupThread: TSGroupThread,
        videoCaptureController: VideoCaptureController
    ) {
        self.commonState = CommonCallState(
            audioActivity: AudioActivity(
                audioDescription: "[SignalCall] with group \(groupThread.groupModel.groupId)",
                behavior: .call
            )
        )
        self.ringRestrictions = []
        self.ringRtcCall = ringRtcCall
        self.groupThread = groupThread
        self.videoCaptureController = videoCaptureController

        self.ringRtcCall.delegate = self

        if groupThread.groupModel.groupMembers.count > RemoteConfig.maxGroupCallRingSize {
            self.ringRestrictions.insert(.groupTooLarge)
        }

        // Track the callInProgress restriction regardless; we use that for
        // purposes other than rings.
        let hasActiveCallMessage = NSObject.databaseStorage.read { transaction -> Bool in
            !GroupCallInteractionFinder().unendedCallsForGroupThread(groupThread, transaction: transaction).isEmpty
        }
        if hasActiveCallMessage {
            // This info may be out of date, but the first peek will update it.
            self.ringRestrictions.insert(.callInProgress)
        }

        // Watch group membership changes. The object is the group thread ID, which
        // is a string. NotificationCenter dispatches by object identity rather
        // than equality, so we watch all changes and filter later.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(groupMembershipDidChange),
            name: TSGroupThread.membershipDidChange,
            object: nil
        )
    }

    var joinState: JoinState {
        return self.ringRtcCall.localDeviceState.joinState
    }

    var hasTerminated: Bool {
        switch groupCallRingState {
        case .incomingRingCancelled:
            return true
        case .doNotRing, .shouldRing, .ringing, .ringingEnded, .incomingRing:
            return false
        }
    }

    // MARK: - Observers

    private var observers: WeakArray<any GroupThreadCallObserver> = []

    func addObserverAndSyncState(_ observer: any GroupThreadCallObserver) {
        AssertIsOnMainThread()

        observers.append(observer)

        // Synchronize observer with current call state
        observer.groupCallLocalDeviceStateChanged(self)
        observer.groupCallRemoteDeviceStatesChanged(self)
    }

    func removeObserver(_ observer: any GroupThreadCallObserver) {
        observers.removeAll(where: { $0 === observer })
    }

    func publishSendFailureUntrustedParticipantIdentity() {
        observers.elements.forEach { $0.callMessageSendFailedUntrustedIdentity(self) }
    }

    // MARK: - Ringing

    struct RingRestrictions: OptionSet {
        var rawValue: UInt8

        /// The user cannot ring because there is already a call in progress.
        static let callInProgress = Self(rawValue: 1 << 1)
        /// This group is too large to allow ringing.
        static let groupTooLarge = Self(rawValue: 1 << 2)
    }

    var ringRestrictions: RingRestrictions {
        didSet {
            AssertIsOnMainThread()
            if ringRestrictions != oldValue, joinState == .notJoined {
                // Use a fake local state change to refresh the call controls.
                //
                // If we ever introduce ringing restrictions for 1:1 calls, a similar
                // affordance will be needed to refresh the call controls.
                self.groupCall(onLocalDeviceStateChanged: ringRtcCall)
            }
        }
    }

    @objc
    private func groupMembershipDidChange(_ notification: Notification) {
        // NotificationCenter dispatches by object identity rather than equality,
        // so we filter based on the thread ID here.
        guard groupThread.uniqueId == notification.object as? String else {
            return
        }
        NSObject.databaseStorage.read(block: groupThread.anyReload(transaction:))
        let groupModel = groupThread.groupModel
        let isGroupTooLarge = groupModel.groupMembers.count > RemoteConfig.maxGroupCallRingSize
        ringRestrictions.update(.groupTooLarge, present: isGroupTooLarge)
    }

    enum GroupCallRingState {
        case doNotRing
        case shouldRing
        case ringing
        case ringingEnded
        case incomingRing(caller: SignalServiceAddress, ringId: Int64)
        case incomingRingCancelled

        var isIncomingRing: Bool {
            switch self {
            case .incomingRing, .incomingRingCancelled:
                return true
            default:
                return false
            }
        }
    }

    var groupCallRingState: GroupCallRingState = .shouldRing {
        didSet {
            AssertIsOnMainThread()
        }
    }
}

// MARK: - GroupCallDelegate

extension GroupThreadCall: GroupCallDelegate {
    public func groupCall(onLocalDeviceStateChanged groupCall: SignalRingRTC.GroupCall) {
        if groupCall.localDeviceState.joinState == .joined, commonState.setConnectedDateIfNeeded() {
            if groupCallRingState.isIncomingRing {
                groupCallRingState = .ringingEnded
            }

            // make sure we don't terminate audio session during call
            NSObject.audioSession.isRTCAudioEnabled = true
            owsAssertDebug(NSObject.audioSession.startAudioActivity(commonState.audioActivity))
        }

        observers.elements.forEach { $0.groupCallLocalDeviceStateChanged(self) }
    }

    public func groupCall(onRemoteDeviceStatesChanged groupCall: SignalRingRTC.GroupCall) {
        observers.elements.forEach { $0.groupCallRemoteDeviceStatesChanged(self) }
        // Change this after notifying observers so that they can see when the ring has concluded.
        if case .ringing = groupCallRingState, !groupCall.remoteDeviceStates.isEmpty {
            groupCallRingState = .ringingEnded
            // Treat the end of ringing as a "local state change" for listeners that normally ignore remote changes.
            self.groupCall(onLocalDeviceStateChanged: groupCall)
        }
    }

    public func groupCall(onAudioLevels groupCall: SignalRingRTC.GroupCall) {
        // TODO: Implement audio level handling for group calls.
    }

    public func groupCall(onLowBandwidthForVideo groupCall: SignalRingRTC.GroupCall, recovered: Bool) {
        // TODO: Implement handling of the "low outgoing bandwidth for video" notification.
    }

    public func groupCall(onReactions groupCall: SignalRingRTC.GroupCall, reactions: [SignalRingRTC.Reaction]) {
        observers.elements.forEach {
            $0.groupCallReceivedReactions(self, reactions: reactions)
        }
    }

    public func groupCall(onRaisedHands groupCall: SignalRingRTC.GroupCall, raisedHands: [UInt32]) {
        guard
            FeatureFlags.callRaiseHandReceiveSupport,
            FeatureFlags.useCallMemberComposableViewsForRemoteUsersInGroupCalls
        else { return }

        self.raisedHands = raisedHands.compactMap { groupCall.remoteDeviceStates[$0] }

        observers.elements.forEach {
            $0.groupCallReceivedRaisedHands(self, raisedHands: raisedHands)
        }
    }

    public func groupCall(onPeekChanged groupCall: SignalRingRTC.GroupCall) {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard let localAci = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci else {
            owsFailDebug("Peek changed for a group call, but we're not registered?")
            return
        }

        if let peekInfo = groupCall.peekInfo {
            // Note that we track this regardless of whether ringing is available.
            // There are other places that use this.

            let minDevicesToConsiderCallInProgress: UInt32 = {
                if peekInfo.joinedMembers.contains(localAci.rawUUID) {
                    // If we're joined, require us + someone else.
                    return 2
                } else {
                    // Otherwise, anyone else in the call counts.
                    return 1
                }
            }()

            ringRestrictions.update(
                .callInProgress,
                present: peekInfo.deviceCountExcludingPendingDevices >= minDevicesToConsiderCallInProgress
            )
        }

        observers.elements.forEach { $0.groupCallPeekChanged(self) }
    }

    public func groupCall(requestMembershipProof groupCall: SignalRingRTC.GroupCall) {
        observers.elements.forEach { $0.groupCallRequestMembershipProof(self) }
    }

    public func groupCall(requestGroupMembers groupCall: SignalRingRTC.GroupCall) {
        observers.elements.forEach { $0.groupCallRequestGroupMembers(self) }
    }

    public func groupCall(onEnded groupCall: SignalRingRTC.GroupCall, reason: GroupCallEndReason) {
        observers.elements.forEach { $0.groupCallEnded(self, reason: reason) }
    }
}

// MARK: - GroupCall

extension GroupCall {
    var isFull: Bool {
        guard let peekInfo = peekInfo, let maxDevices = peekInfo.maxDevices else {
            return false
        }
        return peekInfo.deviceCountExcludingPendingDevices >= maxDevices
    }

    var maxDevices: UInt32? {
        guard let peekInfo = peekInfo, let maxDevices = peekInfo.maxDevices else {
            return nil
        }
        return maxDevices
    }
}
