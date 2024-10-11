//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalRingRTC
import SignalServiceKit
import LibSignalClient
import SignalUI
import UIKit

// MARK: - Call Drawer Protocols

protocol CallDrawerSheetDataSourceObserver: AnyObject {
    func callSheetMembershipDidChange(_ dataSource: CallDrawerSheetDataSource)
    func callSheetRaisedHandsDidChange(_ dataSource: CallDrawerSheetDataSource)
}

@MainActor
protocol CallDrawerSheetDataSource {
    typealias JoinedMember = CallDrawerSheet.JoinedMember

    func unsortedMembers(tx: DBReadTransaction) -> [JoinedMember]

    func raisedHandMemberIds() -> [JoinedMember.ID]
    func raiseHand(raise: Bool)

    func addObserver(_ observer: any CallDrawerSheetDataSourceObserver, syncStateImmediately: Bool)
    func removeObserver(_ observer: any CallDrawerSheetDataSourceObserver)
}

// MARK: - Group Call data source

final class GroupCallSheetDataSource<Call: GroupCall>: CallDrawerSheetDataSource {
    private let ringRtcCall: SignalRingRTC.GroupCall
    private let groupCall: Call

    @MainActor
    init(groupCall: Call) {
        self.ringRtcCall = groupCall.ringRtcCall
        self.groupCall = groupCall

        groupCall.addObserver(self)
    }

    private var observers: WeakArray<any CallDrawerSheetDataSourceObserver> = []
    func addObserver(_ observer: any CallDrawerSheetDataSourceObserver, syncStateImmediately: Bool = false) {
        AssertIsOnMainThread()
        observers.append(observer)
        if syncStateImmediately {
            // Synchronize observer with current call state
            observer.callSheetMembershipDidChange(self)
            observer.callSheetRaisedHandsDidChange(self)
        }
    }

    func removeObserver(_ observer: any CallDrawerSheetDataSourceObserver) {
        observers.removeAll(where: { $0 === observer })
    }

    func raisedHandMemberIds() -> [JoinedMember.ID] {
        return groupCall.raisedHands.map { .demuxID($0) }
    }

    func unsortedMembers(tx: DBReadTransaction) -> [JoinedMember] {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
            return []
        }

        var members = [JoinedMember]()
        let config: DisplayName.ComparableValue.Config = .current()
        if self.ringRtcCall.localDeviceState.joinState == .joined {
            members += self.ringRtcCall.remoteDeviceStates.values.map { member in
                let resolvedName: String
                let comparableName: DisplayName.ComparableValue
                if member.aci == localIdentifiers.aci {
                    resolvedName = OWSLocalizedString(
                        "GROUP_CALL_YOU_ON_ANOTHER_DEVICE",
                        comment: "Text describing the local user in the group call members sheet when connected from another device."
                    )
                    comparableName = .nameValue(resolvedName)
                } else {
                    let displayName = SSKEnvironment.shared.contactManagerRef.displayName(for: member.address, tx: SDSDB.shimOnlyBridge(tx))
                    resolvedName = displayName.resolvedValue(config: config.displayNameConfig)
                    comparableName = displayName.comparableValue(config: config)
                }

                return JoinedMember(
                    id: .demuxID(member.demuxId),
                    aci: member.aci,
                    displayName: resolvedName,
                    comparableName: comparableName,
                    demuxID: member.demuxId,
                    isLocalUser: false,
                    isUnknown: false,
                    isAudioMuted: member.audioMuted,
                    isVideoMuted: member.videoMuted,
                    isPresenting: member.presenting
                )
            }

            let displayName = CommonStrings.you
            let comparableName: DisplayName.ComparableValue = .nameValue(displayName)
            let id: JoinedMember.ID
            let demuxId: UInt32?
            if let localDemuxId = ringRtcCall.localDeviceState.demuxId {
                id = .demuxID(localDemuxId)
                demuxId = localDemuxId
            } else {
                id = .aci(localIdentifiers.aci)
                demuxId = nil
            }
            members.append(JoinedMember(
                id: id,
                aci: localIdentifiers.aci,
                displayName: displayName,
                comparableName: comparableName,
                demuxID: demuxId,
                isLocalUser: true,
                isUnknown: false,
                isAudioMuted: self.ringRtcCall.isOutgoingAudioMuted,
                isVideoMuted: self.ringRtcCall.isOutgoingVideoMuted,
                isPresenting: false
            ))
        } else {
            // If we're not yet in the call, `remoteDeviceStates` will not exist.
            // We can get the list of joined members still, provided we are connected.
            members += self.ringRtcCall.peekInfo?.joinedMembers.map { aciUuid in
                let aci = Aci(fromUUID: aciUuid)
                let address = SignalServiceAddress(aci)
                let displayName = SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: SDSDB.shimOnlyBridge(tx))
                let isUnknown = switch displayName {
                case .nickname, .systemContactName, .profileName, .phoneNumber, .username:
                    false
                case .unknown, .deletedAccount:
                    true
                }
                return JoinedMember(
                    id: .aci(aci),
                    aci: aci,
                    displayName: displayName.resolvedValue(config: config.displayNameConfig),
                    comparableName: displayName.comparableValue(config: config),
                    demuxID: nil,
                    isLocalUser: false,
                    isUnknown: isUnknown,
                    isAudioMuted: nil,
                    isVideoMuted: nil,
                    isPresenting: nil
                )
            } ?? []
        }
        return members
    }
}

// MARK: GroupCallObserver

extension GroupCallSheetDataSource: GroupCallObserver {
    func groupCallLocalDeviceStateChanged(_ call: GroupCall) {
        AssertIsOnMainThread()
        observers.elements.forEach { $0.callSheetMembershipDidChange(self) }
    }

    func groupCallRemoteDeviceStatesChanged(_ call: GroupCall) {
        AssertIsOnMainThread()
        observers.elements.forEach { $0.callSheetMembershipDidChange(self) }
    }

    func groupCallPeekChanged(_ call: GroupCall) {
        AssertIsOnMainThread()
        observers.elements.forEach { $0.callSheetMembershipDidChange(self) }
    }

    func groupCallEnded(_ call: GroupCall, reason: GroupCallEndReason) {
        AssertIsOnMainThread()
        observers.elements.forEach { $0.callSheetMembershipDidChange(self) }
    }

    func groupCallReceivedRaisedHands(_ call: GroupCall, raisedHands: [DemuxId]) {
        AssertIsOnMainThread()
        observers.elements.forEach { $0.callSheetRaisedHandsDidChange(self) }
    }

    func raiseHand(raise: Bool) {
        ringRtcCall.raiseHand(raise: raise)
    }
}

// MARK: Call Links

typealias CallLinkSheetDataSource = GroupCallSheetDataSource<CallLinkCall>

extension CallLinkSheetDataSource {
    func url() -> URL {
        return self.groupCall.callLink.url()
    }

    var callLink: CallLink {
        self.groupCall.callLink
    }

    var isAdmin: Bool {
        self.groupCall.adminPasskey != nil
    }

    var adminPasskey: Data? {
        self.groupCall.adminPasskey
    }

    var callLinkState: SignalServiceKit.CallLinkState {
        self.groupCall.callLinkState
    }

    func removeMember(demuxId: DemuxId) {
        ringRtcCall.removeClient(demuxId: demuxId)
    }

    func blockMember(demuxId: DemuxId) {
        ringRtcCall.blockClient(demuxId: demuxId)
    }
}

// MARK: - Individual call data source

class IndividualCallSheetDataSource: CallDrawerSheetDataSource {

    private var call: SignalCall
    private var individualCall: IndividualCall
    private var thread: TSContactThread

    init(
        thread: TSContactThread,
        call: SignalCall,
        individualCall: IndividualCall
    ) {
        self.call = call
        self.thread = thread
        self.individualCall = individualCall
        individualCall.addObserverAndSyncState(self)
    }

    func unsortedMembers(tx: any SignalServiceKit.DBReadTransaction) -> [JoinedMember] {
        var members = [JoinedMember]()

        if let remoteAci = thread.contactAddress.aci {
            let remoteDisplayName = SSKEnvironment.shared.contactManagerRef.displayName(
                for: thread.contactAddress,
                tx: SDSDB.shimOnlyBridge(tx)
            ).resolvedValue()
            let remoteComparableName: DisplayName.ComparableValue = .nameValue(remoteDisplayName)
            members.append(JoinedMember(
                id: .aci(remoteAci),
                aci: remoteAci,
                displayName: remoteDisplayName,
                comparableName: remoteComparableName,
                demuxID: nil,
                isLocalUser: false,
                isUnknown: false,
                isAudioMuted: self.individualCall.isRemoteAudioMuted,
                isVideoMuted: self.individualCall.isRemoteVideoEnabled.negated,
                isPresenting: self.individualCall.isRemoteSharingScreen
            ))
        }

        // Add yourself
        let displayName = CommonStrings.you
        let comparableName: DisplayName.ComparableValue = .nameValue(displayName)
        if let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aci {
            members.append(JoinedMember(
                id: .aci(localAci),
                aci: localAci,
                displayName: displayName,
                comparableName: comparableName,
                demuxID: nil,
                isLocalUser: true,
                isUnknown: false,
                isAudioMuted: self.call.isOutgoingAudioMuted,
                isVideoMuted: self.call.isOutgoingVideoMuted,
                isPresenting: false
            ))
        }
        return members
    }

    func raisedHandMemberIds() -> [JoinedMember.ID] {[]}
    func raiseHand(raise: Bool) {
        owsFailDebug("Should not be able to raise hand in individual call")
    }

    private var observers: WeakArray<any CallDrawerSheetDataSourceObserver> = []
    func addObserver(_ observer: any CallDrawerSheetDataSourceObserver, syncStateImmediately: Bool = false) {
        AssertIsOnMainThread()
        observers.append(observer)
        if syncStateImmediately {
            // Synchronize observer with current call state
            observer.callSheetMembershipDidChange(self)
            observer.callSheetRaisedHandsDidChange(self)
        }
    }

    func removeObserver(_ observer: any CallDrawerSheetDataSourceObserver) {
        observers.removeAll(where: { $0 === observer })
    }
}

// MARK: IndividualCallObserver

extension IndividualCallSheetDataSource: IndividualCallObserver {
    func individualCallStateDidChange(_ call: IndividualCall, state: CallState) {
        AssertIsOnMainThread()
        observers.elements.forEach { $0.callSheetMembershipDidChange(self) }
    }

    func individualCallLocalVideoMuteDidChange(_ call: IndividualCall, isVideoMuted: Bool) {
        AssertIsOnMainThread()
        observers.elements.forEach { $0.callSheetMembershipDidChange(self) }
    }

    func individualCallLocalAudioMuteDidChange(_ call: IndividualCall, isAudioMuted: Bool) {
        AssertIsOnMainThread()
        observers.elements.forEach { $0.callSheetMembershipDidChange(self) }
    }

    func individualCallHoldDidChange(_ call: IndividualCall, isOnHold: Bool) {
        AssertIsOnMainThread()
        observers.elements.forEach { $0.callSheetMembershipDidChange(self) }
    }

    func individualCallRemoteAudioMuteDidChange(_ call: IndividualCall, isAudioMuted: Bool) {
        AssertIsOnMainThread()
        observers.elements.forEach { $0.callSheetMembershipDidChange(self) }
    }

    func individualCallRemoteVideoMuteDidChange(_ call: IndividualCall, isVideoMuted: Bool) {
        AssertIsOnMainThread()
        observers.elements.forEach { $0.callSheetMembershipDidChange(self) }
    }

    func individualCallRemoteSharingScreenDidChange(_ call: IndividualCall, isRemoteSharingScreen: Bool) {
        AssertIsOnMainThread()
        observers.elements.forEach { $0.callSheetMembershipDidChange(self) }
    }
}
