//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalRingRTC
import SignalServiceKit
import LibSignalClient
import UIKit

struct JoinedMember {
    enum ID: Hashable {
        case aci(Aci)
        case demuxID(DemuxId)
    }

    let id: ID

    let aci: Aci
    let displayName: String
    let comparableName: DisplayName.ComparableValue
    let demuxID: DemuxId?
    let isLocalUser: Bool
    let isAudioMuted: Bool?
    let isVideoMuted: Bool?
    let isPresenting: Bool?
}

protocol CallSheetDataSourceObserver: AnyObject {
    func callSheetMembershipDidChange(_ dataSource: CallSheetDataSource)
    func callSheetRaisedHandsDidChange(_ dataSource: CallSheetDataSource)
}

protocol CallSheetDataSource {
    func unsortedMembers(tx: DBReadTransaction) -> [JoinedMember]

    func raisedHandMemberIds() -> [JoinedMember.ID]

    func addObserver(_ observer: any CallSheetDataSourceObserver, syncStateImmediately: Bool)
    func removeObserver(_ observer: any CallSheetDataSourceObserver)
//    var tableViewDataSource: DiffableDataSource { get }
}

class GroupCallSheetDataSource: CallSheetDataSource {

    private let ringRtcCall: SignalRingRTC.GroupCall
    private let groupThreadCall: GroupThreadCall
    init(groupThreadCall: GroupThreadCall) {
        self.ringRtcCall = groupThreadCall.ringRtcCall
        self.groupThreadCall = groupThreadCall

        groupThreadCall.addObserver(self)
    }

    private var observers: WeakArray<any CallSheetDataSourceObserver> = []
    func addObserver(_ observer: any CallSheetDataSourceObserver, syncStateImmediately: Bool = false) {
        AssertIsOnMainThread()
        observers.append(observer)
        if syncStateImmediately {
            // Synchronize observer with current call state
            observer.callSheetMembershipDidChange(self)
            observer.callSheetRaisedHandsDidChange(self)
        }
    }

    func removeObserver(_ observer: any CallSheetDataSourceObserver) {
        observers.removeAll(where: { $0 === observer })
    }

    func raisedHandMemberIds() -> [JoinedMember.ID] {
        return groupThreadCall.raisedHands.map { .demuxID($0) }
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
                    let displayName = NSObject.contactsManager.displayName(for: member.address, tx: SDSDB.shimOnlyBridge(tx))
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
                let displayName = NSObject.contactsManager.displayName(for: address, tx: SDSDB.shimOnlyBridge(tx))
                return JoinedMember(
                    id: .aci(aci),
                    aci: aci,
                    displayName: displayName.resolvedValue(config: config.displayNameConfig),
                    comparableName: displayName.comparableValue(config: config),
                    demuxID: nil,
                    isLocalUser: false,
                    isAudioMuted: nil,
                    isVideoMuted: nil,
                    isPresenting: nil
                )
            } ?? []
        }

        return members
    }
}

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
}

class IndividualCallSheetDataSource: CallSheetDataSource {

    private var individualCall: IndividualCall
    init(individualCall: IndividualCall) {
        self.individualCall = individualCall
        individualCall.addObserverAndSyncState(self)
    }

    func unsortedMembers(tx: any SignalServiceKit.DBReadTransaction) -> [JoinedMember] {
        return []
    }

    func raisedHandMemberIds() -> [JoinedMember.ID] {[]}

    private var observers: WeakArray<any CallSheetDataSourceObserver> = []
    func addObserver(_ observer: any CallSheetDataSourceObserver, syncStateImmediately: Bool = false) {
        AssertIsOnMainThread()
        observers.append(observer)
        if syncStateImmediately {
            // Synchronize observer with current call state
            observer.callSheetMembershipDidChange(self)
            observer.callSheetRaisedHandsDidChange(self)
        }
    }

    func removeObserver(_ observer: any CallSheetDataSourceObserver) {
        observers.removeAll(where: { $0 === observer })
    }
}

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

    func individualCallRemoteVideoMuteDidChange(_ call: IndividualCall, isVideoMuted: Bool) {
        AssertIsOnMainThread()
        observers.elements.forEach { $0.callSheetMembershipDidChange(self) }
    }

    func individualCallRemoteSharingScreenDidChange(_ call: IndividualCall, isRemoteSharingScreen: Bool) {
        AssertIsOnMainThread()
        observers.elements.forEach { $0.callSheetMembershipDidChange(self) }
    }
}
