//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalRingRTC
import SignalServiceKit

/// Cleans up any group calls "stuck" in the ringing state.
///
/// After a group call rings (i.e., RingRTC gives the app a group ring update
/// indicating a new ring was requested), it is either accepted/declined by the
/// user or expires if unanswered for too long. Expiration is signaled by
/// another RingRTC ring update.
///
/// However, if app execution is interrupted while the call is ringing it's
/// possible that the app will never receive the "ring expired" ring update from
/// RingRTC. (This is due to RingRTC behavior – "ring expired" messages are not
/// delivered if the app is offline for sufficiently long after the expiration.)
///
/// This manager is a backstop responsible for finding any calls stuck in that
/// state and moving them to the terminal "ringing missed" state.
///
/// It will also attempt to determine if the most recent calls in this state are
/// still ongoing, and if so will notify the user as if the call had just
/// started.
final class GroupCallRecordRingingCleanupManager {
    private enum Constants {
        /// The max number of ringing calls to peek to determine if they are
        /// still ongoing. Any calls beyond this limit will not be peeked, and
        /// will be assumed to have ended.
        static let maxRingingCallsToPeek: Int = 10
    }

    private let callRecordStore: CallRecordStore
    private let callRecordQuerier: CallRecordQuerier
    private let db: any DB
    private let interactionStore: InteractionStore
    private let groupCallPeekClient: GroupCallPeekClient
    private let notificationPresenter: Shims.NotificationPresenter
    private let threadStore: ThreadStore

    init(
        callRecordStore: CallRecordStore,
        callRecordQuerier: CallRecordQuerier,
        db: any DB,
        interactionStore: InteractionStore,
        groupCallPeekClient: GroupCallPeekClient,
        notificationPresenter: NotificationPresenter,
        threadStore: ThreadStore
    ) {
        self.callRecordStore = callRecordStore
        self.callRecordQuerier = callRecordQuerier
        self.db = db
        self.interactionStore = interactionStore
        self.groupCallPeekClient = groupCallPeekClient
        self.notificationPresenter = Wrappers.NotificationPresenter(notificationPresenter: notificationPresenter)
        self.threadStore = threadStore
    }

    func cleanupRingingCalls(tx: DBWriteTransaction) {
        guard
            let ringingGroupCallCursor = callRecordQuerier.fetchCursor(
                callStatus: .group(.ringing),
                ordering: .descending,
                tx: tx
            ),
            let ringingCallRecords = try? ringingGroupCallCursor.drain()
        else { return }

        guard !ringingCallRecords.isEmpty else {
            // This should be the 99% case, since having a call in the "ringing"
            // state on launch means something went wrong in a previous launch.
            return
        }

        // We'll peek the group calls from the most recent ringing call records
        // to see if the call is still ongoing.
        let callRecordsToPeek = ringingCallRecords.prefix(Constants.maxRingingCallsToPeek)

        for ringingCallRecord in ringingCallRecords {
            callRecordStore.updateCallAndUnreadStatus(
                callRecord: ringingCallRecord,
                newCallStatus: .group(.ringingMissed),
                tx: tx
            )
        }

        /// A little chunky – group by the group thread row ID, then map those
        /// groupings to load the group thread for each row ID.
        let callRecordsByGroupId: [(GroupIdentifier, [CallRecord])] = Dictionary(
            grouping: callRecordsToPeek,
            by: { $0.conversationId }
        ).compactMap { (conversationId, callRecords) -> (GroupIdentifier, [CallRecord])? in
            switch conversationId {
            case .thread(let threadRowId):
                guard
                    let groupThread = threadStore.fetchThread(rowId: threadRowId, tx: tx) as? TSGroupThread,
                    let groupId = try? groupThread.groupIdentifier
                else {
                    return nil
                }
                return (groupId, callRecords)
            case .callLink(_):
                return nil
            }
        }

        for (groupId, callRecords) in callRecordsByGroupId {
            Task {
                try await peekGroupAndNotifyIfNecessary(
                    groupId: groupId,
                    callRecords: callRecords
                )
            }
        }
    }

    /// Peeks the group thread and compares the current group call against the
    /// ringing group call records in it. If the current call for a group
    /// matches one of the records for the group (i.e., the call that created
    /// the ringing record is still ongoing), posts a notification.
    private func peekGroupAndNotifyIfNecessary(
        groupId: GroupIdentifier,
        callRecords: [CallRecord]
    ) async throws {
        let peekInfo = try await self.groupCallPeekClient.fetchPeekInfo(groupId: groupId)
        let callId = peekInfo.eraId.map({ callIdFromEra($0) })

        await self.db.awaitableWrite { tx in
            // Reload the group thread, since it may have changed.
            guard let groupThread = self.threadStore.fetchGroupThread(groupId: groupId, tx: tx) else {
                owsFail("Where did the thread go?")
            }

            let interactionRowIdsMatchingCurrentCall = callRecords.compactMap { callRecord -> Int64? in
                switch callRecord.interactionReference {
                case .thread(let threadRowId, let interactionRowId):
                    owsPrecondition(threadRowId == groupThread.sqliteRowId!)
                    guard callRecord.callId == callId else {
                        return nil
                    }
                    return interactionRowId
                case .none:
                    owsFail("Must pass callRecords for groupThread.")
                }
            }

            owsAssertDebug(interactionRowIdsMatchingCurrentCall.count <= 1)

            for interactionRowId in interactionRowIdsMatchingCurrentCall {
                let interaction = self.interactionStore.fetchInteraction(rowId: interactionRowId, tx: tx)
                guard let groupCallInteraction = interaction as? OWSGroupCallMessage else {
                    continue
                }

                self.notificationPresenter.notifyUserGroupCallStarted(
                    groupCallInteraction: groupCallInteraction,
                    groupThread: groupThread,
                    tx: tx
                )
            }
        }
    }
}

// MARK: - Shims

private extension GroupCallRecordRingingCleanupManager {
    enum Shims {
        typealias NotificationPresenter = GroupCallRecordRingingCleanupManager_NotificationPresenter_Shim
    }

    enum Wrappers {
        typealias NotificationPresenter = GroupCallRecordRingingCleanupManager_NotificationPresenter_Wrapper
    }
}

private protocol GroupCallRecordRingingCleanupManager_NotificationPresenter_Shim {
    func notifyUserGroupCallStarted(
        groupCallInteraction: OWSGroupCallMessage,
        groupThread: TSGroupThread,
        tx: DBWriteTransaction
    )
}

final private class GroupCallRecordRingingCleanupManager_NotificationPresenter_Wrapper: GroupCallRecordRingingCleanupManager_NotificationPresenter_Shim {
    private let notificationPresenter: any NotificationPresenter

    init(notificationPresenter: any NotificationPresenter) {
        self.notificationPresenter = notificationPresenter
    }

    func notifyUserGroupCallStarted(
        groupCallInteraction: OWSGroupCallMessage,
        groupThread: TSGroupThread,
        tx: DBWriteTransaction
    ) {
        notificationPresenter.notifyUser(
            forPreviewableInteraction: groupCallInteraction,
            thread: groupThread,
            wantsSound: true,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }
}
