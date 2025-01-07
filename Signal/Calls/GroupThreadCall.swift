//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalRingRTC
import SignalServiceKit
import SignalUI

protocol GroupThreadCallDelegate: AnyObject {
    func groupThreadCallRequestMembershipProof(_ call: GroupThreadCall)
    func groupThreadCallRequestGroupMembers(_ call: GroupThreadCall)
}

final class GroupThreadCall: Signal.GroupCall {
    private weak var delegate: (any GroupThreadCallDelegate)?

    let groupId: GroupIdentifier
    let threadUniqueId: String
    var membershipDidChangeObserver: (any NSObjectProtocol)!

    init?(
        delegate: any GroupThreadCallDelegate,
        ringRtcCall: SignalRingRTC.GroupCall,
        groupId: GroupIdentifier,
        videoCaptureController: VideoCaptureController
    ) {
        self.delegate = delegate
        self.groupId = groupId

        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let groupThread = databaseStorage.read { tx in
            return TSGroupThread.fetch(forGroupId: groupId, tx: tx)
        }
        guard let groupThread else {
            owsFailDebug("Missing thread for active call.")
            return nil
        }

        self.threadUniqueId = groupThread.uniqueId

        super.init(
            audioDescription: "[SignalCall] with group \(groupId.serialize().asData)",
            ringRtcCall: ringRtcCall,
            videoCaptureController: videoCaptureController
        )

        if groupThread.groupModel.groupMembers.count > RemoteConfig.current.maxGroupCallRingSize {
            self.ringRestrictions.insert(.groupTooLarge)
        }

        // Track the callInProgress restriction regardless; we use that for
        // purposes other than rings.
        let hasActiveCallMessage = SSKEnvironment.shared.databaseStorageRef.read { transaction -> Bool in
            !GroupCallInteractionFinder().unendedCallsForGroupThread(groupThread, transaction: transaction).isEmpty
        }
        if hasActiveCallMessage {
            // This info may be out of date, but the first peek will update it.
            self.ringRestrictions.insert(.callInProgress)
        }

        // Watch group membership changes. The object is the group thread ID, which
        // is a string. NotificationCenter dispatches by object identity rather
        // than equality, so we watch all changes and filter later.
        self.membershipDidChangeObserver = NotificationCenter.default.addObserver(forName: TSGroupThread.membershipDidChange, object: nil, queue: .main) { [weak self] notification in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.groupMembershipDidChange(notification)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(membershipDidChangeObserver!)
    }

    var hasTerminated: Bool {
        switch groupCallRingState {
        case .incomingRingCancelled:
            return true
        case .doNotRing, .shouldRing, .ringing, .ringingEnded, .incomingRing:
            return false
        }
    }

    // MARK: - Ringing

    struct RingRestrictions: OptionSet {
        var rawValue: UInt8

        /// The user cannot ring because there is already a call in progress.
        static let callInProgress = Self(rawValue: 1 << 1)
        /// This group is too large to allow ringing.
        static let groupTooLarge = Self(rawValue: 1 << 2)
    }

    @MainActor
    var ringRestrictions: RingRestrictions = [] {
        didSet {
            if ringRestrictions != oldValue, joinState == .notJoined {
                // Use a fake local state change to refresh the call controls.
                //
                // If we ever introduce ringing restrictions for 1:1 calls, a similar
                // affordance will be needed to refresh the call controls.
                self.groupCall(onLocalDeviceStateChanged: ringRtcCall)
            }
        }
    }

    @MainActor
    private func groupMembershipDidChange(_ notification: Notification) {
        // NotificationCenter dispatches by object identity rather than equality,
        // so we filter based on the thread ID here.
        guard threadUniqueId == notification.object as? String else {
            return
        }
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let groupThread = databaseStorage.read { tx in
            return TSGroupThread.fetch(forGroupId: groupId, tx: tx)
        }
        guard let groupThread else {
            owsFailDebug("Missing group thread for active call.")
            return
        }
        let groupModel = groupThread.groupModel
        let isGroupTooLarge = groupModel.groupMembers.count > RemoteConfig.current.maxGroupCallRingSize
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
    }

    override func groupCall(onRemoteDeviceStatesChanged groupCall: SignalRingRTC.GroupCall) {
        super.groupCall(onRemoteDeviceStatesChanged: groupCall)

        // Change this after notifying observers so that they can see when the ring has concluded.
        if case .ringing = groupCallRingState, !groupCall.remoteDeviceStates.isEmpty {
            groupCallRingState = .ringingEnded
            // Treat the end of ringing as a "local state change" for listeners that normally ignore remote changes.
            self.groupCall(onLocalDeviceStateChanged: groupCall)
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
    }

    override func groupCall(requestMembershipProof groupCall: SignalRingRTC.GroupCall) {
        super.groupCall(requestMembershipProof: groupCall)

        delegate?.groupThreadCallRequestMembershipProof(self)
    }

    override func groupCall(requestGroupMembers groupCall: SignalRingRTC.GroupCall) {
        super.groupCall(requestGroupMembers: groupCall)

        delegate?.groupThreadCallRequestGroupMembers(self)
    }
}

// MARK: - GroupCall

extension SignalRingRTC.GroupCall {
    var isFull: Bool {
        guard let peekInfo = peekInfo, let maxDevices = peekInfo.maxDevices else {
            return false
        }
        return peekInfo.deviceCountIncludingPendingDevices >= maxDevices
    }

    var maxDevices: UInt32? {
        guard let peekInfo = peekInfo, let maxDevices = peekInfo.maxDevices else {
            return nil
        }
        return maxDevices
    }
}
