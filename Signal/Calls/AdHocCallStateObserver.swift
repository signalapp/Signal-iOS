//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalRingRTC
import SignalServiceKit

final class AdHocCallStateObserver {
    private let adHocCallRecordManager: any AdHocCallRecordManager
    private let callLinkStore: any CallLinkRecordStore
    private let db: any DB
    private let messageSenderJobQueue: MessageSenderJobQueue

    private let callLinkCall: CallLinkCall

    private enum JoinLevel: Int, Comparable {
        case attempted
        case joined

        static func < (lhs: Self, rhs: Self) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    /// The furthest we've ever gotten in this instance of this call. If we
    /// intentionally leave and join again, we'll reset this value. We use this
    /// to avoid redundant db queries, not for correctness.
    private var furthestJoinLevel: JoinLevel?

    init(
        callLinkCall: CallLinkCall,
        adHocCallRecordManager: any AdHocCallRecordManager,
        callLinkStore: any CallLinkRecordStore,
        messageSenderJobQueue: MessageSenderJobQueue,
        db: any DB
    ) {
        self.callLinkCall = callLinkCall
        self.adHocCallRecordManager = adHocCallRecordManager
        self.callLinkStore = callLinkStore
        self.messageSenderJobQueue = messageSenderJobQueue
        self.db = db
    }

    func checkIfJoined() {
        let ringRtcCall = self.callLinkCall.ringRtcCall
        guard let eraId = ringRtcCall.peekInfo?.eraId else {
            return
        }
        let joinLevel: JoinLevel
        switch ringRtcCall.localDeviceState.joinState {
        case .notJoined:
            return
        case .pending, .joining:
            joinLevel = .attempted
        case .joined:
            joinLevel = .joined
        }
        if let furthestJoinLevel, joinLevel <= furthestJoinLevel {
            return
        }
        self.furthestJoinLevel = joinLevel
        db.write { tx in
            do {
                let rootKey = callLinkCall.callLink.rootKey
                var (callLink, inserted) = try callLinkStore.fetchOrInsert(rootKey: rootKey, tx: tx)
                if inserted {
                    callLink.updateState(callLinkCall.callLinkState)
                    try callLinkStore.update(callLink, tx: tx)
                }
                if callLink.adminPasskey == nil, !callLink.isDeleted {
                    let updateSender = CallLinkUpdateMessageSender(messageSenderJobQueue: messageSenderJobQueue)
                    updateSender.sendCallLinkUpdateMessage(rootKey: rootKey, adminPasskey: nil, tx: SDSDB.shimOnlyBridge(tx))
                }
                try adHocCallRecordManager.createOrUpdateRecord(
                    callId: callIdFromEra(eraId),
                    callLink: callLink,
                    status: { () -> CallRecord.CallStatus.CallLinkCallStatus in
                        switch joinLevel {
                        case .attempted: return .generic
                        case .joined: return .joined
                        }
                    }(),
                    timestamp: Date.ows_millisecondTimestamp(),
                    shouldSendSyncMessge: true,
                    tx: tx
                )
            } catch {
                owsFailDebug("Couldn't update CallRecord: \(error)")
            }
        }
    }

    private var activeEraId: String??

    /// Updates `CallLinkRecord.activeCallId` during the call/in the lobby.
    func checkIfActive() {
        let ringRtcCall = self.callLinkCall.ringRtcCall
        guard let peekInfo = ringRtcCall.peekInfo else {
            return
        }
        guard self.activeEraId != .some(peekInfo.eraId) else {
            return
        }
        self.activeEraId = .some(peekInfo.eraId)
        db.write { tx in
            do {
                try adHocCallRecordManager.handlePeekResult(
                    eraId: peekInfo.eraId,
                    rootKey: self.callLinkCall.callLink.rootKey,
                    tx: tx
                )
            } catch {
                owsFailDebug("\(error)")
            }
        }
    }
}
