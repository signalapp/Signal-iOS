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

final class GroupThreadCall: Signal.GroupCall {
    let groupThread: TSGroupThread

    init(
        ringRtcCall: SignalRingRTC.GroupCall,
        groupThread: TSGroupThread,
        videoCaptureController: VideoCaptureController
    ) {
        self.groupThread = groupThread

        super.init(
            audioDescription: "[SignalCall] with group \(groupThread.groupModel.groupId)",
            ringRtcCall: ringRtcCall,
            videoCaptureController: videoCaptureController
        )

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

    var ringRestrictions: RingRestrictions = [] {
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

    // MARK: - GroupCallDelegate

    override func groupCall(onLocalDeviceStateChanged groupCall: SignalRingRTC.GroupCall) {
        if groupCallRingState.isIncomingRing, groupCall.localDeviceState.joinState == .joined {
            groupCallRingState = .ringingEnded
        }

        super.groupCall(onLocalDeviceStateChanged: groupCall)

        observers.elements.forEach { $0.groupCallLocalDeviceStateChanged(self) }
    }

    override func groupCall(onRemoteDeviceStatesChanged groupCall: SignalRingRTC.GroupCall) {
        super.groupCall(onRemoteDeviceStatesChanged: groupCall)

        observers.elements.forEach { $0.groupCallRemoteDeviceStatesChanged(self) }

        // Change this after notifying observers so that they can see when the ring has concluded.
        if case .ringing = groupCallRingState, !groupCall.remoteDeviceStates.isEmpty {
            groupCallRingState = .ringingEnded
            // Treat the end of ringing as a "local state change" for listeners that normally ignore remote changes.
            self.groupCall(onLocalDeviceStateChanged: groupCall)
        }
    }

    override func groupCall(onReactions groupCall: SignalRingRTC.GroupCall, reactions: [SignalRingRTC.Reaction]) {
        super.groupCall(onReactions: groupCall, reactions: reactions)

        observers.elements.forEach {
            $0.groupCallReceivedReactions(self, reactions: reactions)
        }
    }

    override func groupCall(onRaisedHands groupCall: SignalRingRTC.GroupCall, raisedHands: [UInt32]) {
        super.groupCall(onRaisedHands: groupCall, raisedHands: raisedHands)

        guard
            FeatureFlags.callRaiseHandReceiveSupport,
            FeatureFlags.useCallMemberComposableViewsForRemoteUsersInGroupCalls
        else { return }

        observers.elements.forEach {
            $0.groupCallReceivedRaisedHands(self, raisedHands: raisedHands)
        }
    }

    override func groupCall(onPeekChanged groupCall: SignalRingRTC.GroupCall) {
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

        super.groupCall(onPeekChanged: groupCall)

        observers.elements.forEach { $0.groupCallPeekChanged(self) }
    }

    override func groupCall(requestMembershipProof groupCall: SignalRingRTC.GroupCall) {
        super.groupCall(requestMembershipProof: groupCall)

        observers.elements.forEach { $0.groupCallRequestMembershipProof(self) }
    }

    override func groupCall(requestGroupMembers groupCall: SignalRingRTC.GroupCall) {
        super.groupCall(requestGroupMembers: groupCall)

        observers.elements.forEach { $0.groupCallRequestGroupMembers(self) }
    }

    override func groupCall(onEnded groupCall: SignalRingRTC.GroupCall, reason: GroupCallEndReason) {
        super.groupCall(onEnded: groupCall, reason: reason)

        observers.elements.forEach { $0.groupCallEnded(self, reason: reason) }
    }
}

// MARK: - GroupCall

extension SignalRingRTC.GroupCall {
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
