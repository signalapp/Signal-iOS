//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugUICallsTab: DebugUIPage {
    private var callRecordStore: CallRecordStore { DependenciesBridge.shared.callRecordStore }
    private var databaseStorage: SDSDatabaseStorage { SSKEnvironment.shared.databaseStorage }

    private var _nowTimestamp: UInt64 = Date().ows_millisecondsSince1970
    private var nowTimestamp: UInt64 {
        let now = _nowTimestamp
        _nowTimestamp += 1
        return now
    }

    let name: String = "Calls Tab"

    func section(thread: TSThread?) -> OWSTableSection? {
        return tableItems(thread: thread).map { items in
            return OWSTableSection(title: name, items: items)
        }
    }

    private func tableItems(thread: TSThread?) -> [OWSTableItem]? {
        if let contactThread = thread as? TSContactThread {
            return [
                OWSTableItem(title: "Create incoming, accepted call", actionBlock: {
                    self.databaseStorage.write { tx in
                        self.createIncomingAcceptedCall(contactThread: contactThread, tx: tx)
                    }
                }),
                OWSTableItem(title: "Create incoming, missed call", actionBlock: {
                    self.databaseStorage.write { tx in
                        self.createIncomingAcceptedCall(contactThread: contactThread, tx: tx)
                    }
                }),
                OWSTableItem(title: "Create outgoing, accepted call", actionBlock: {
                    self.databaseStorage.write { tx in
                        self.createIncomingAcceptedCall(contactThread: contactThread, tx: tx)
                    }
                }),
                OWSTableItem(title: "Create outgoing, missed call", actionBlock: {
                    self.databaseStorage.write { tx in
                        self.createIncomingAcceptedCall(contactThread: contactThread, tx: tx)
                    }
                }),
            ]
        } else if let groupThread = thread as? TSGroupThread {
            return [
                OWSTableItem(title: "Create generic call", actionBlock: {
                    self.databaseStorage.write { tx in
                        self.createGenericCall(groupThread: groupThread, tx: tx)
                    }
                }),
                OWSTableItem(title: "Create joined call", actionBlock: {
                    self.databaseStorage.write { tx in
                        self.createJoinedCall(groupThread: groupThread, tx: tx)
                    }
                }),
                OWSTableItem(title: "Create incoming ringing accepted call", actionBlock: {
                    self.databaseStorage.write { tx in
                        self.createRingingAcceptedCall(groupThread: groupThread, tx: tx)
                    }
                }),
                OWSTableItem(title: "Create incoming ringing declined call", actionBlock: {
                    self.databaseStorage.write { tx in
                        self.createRingingDeclinedCall(groupThread: groupThread, tx: tx)
                    }
                }),
                OWSTableItem(title: "Create outgoing ringing call", actionBlock: {
                    self.databaseStorage.write { tx in
                        self.createOutgoingRingingCall(groupThread: groupThread, tx: tx)
                    }
                }),
            ]
        } else if thread == nil {
            return [
                OWSTableItem(title: "Create incoming, accepted calls for all threads", actionBlock: {
                    self.enumerateThreads(
                        contactThreadBlock: { contactThread, tx in
                            self.createIncomingAcceptedCall(contactThread: contactThread, tx: tx)
                        },
                        groupThreadBlock: { groupThread, tx in
                            self.createGenericCall(groupThread: groupThread, tx: tx)
                            self.createJoinedCall(groupThread: groupThread, tx: tx)
                            self.createRingingAcceptedCall(groupThread: groupThread, tx: tx)
                        }
                    )
                }),
                OWSTableItem(title: "Create incoming, missed calls for all threads", actionBlock: {
                    self.enumerateThreads(
                        contactThreadBlock: { contactThread, tx in
                            self.createIncomingMissedCall(contactThread: contactThread, tx: tx)
                        },
                        groupThreadBlock: { groupThread, tx in
                            self.createRingingDeclinedCall(groupThread: groupThread, tx: tx)
                        }
                    )
                }),
                OWSTableItem(title: "Create outgoing calls for all threads", actionBlock: {
                    self.enumerateThreads(
                        contactThreadBlock: { contactThread, tx in
                            self.createOutgoingAcceptedCall(contactThread: contactThread, tx: tx)
                            self.createOutgoingMissedCall(contactThread: contactThread, tx: tx)
                        },
                        groupThreadBlock: { groupThread, tx in
                            self.createOutgoingRingingCall(groupThread: groupThread, tx: tx)
                        }
                    )
                }),
            ]
        }

        return nil
    }

    // MARK: Individual calls

    private func createIncomingAcceptedCall(
        contactThread: TSContactThread,
        tx: SDSAnyWriteTransaction
    ) {
        createIndividualCall(
            contactThread: contactThread,
            callDirection: .incoming,
            callType: .incoming,
            individualCallStatus: .accepted,
            tx: tx
        )
    }

    private func createIncomingMissedCall(
        contactThread: TSContactThread,
        tx: SDSAnyWriteTransaction
    ) {
        createIndividualCall(
            contactThread: contactThread,
            callDirection: .incoming,
            callType: .incomingMissed,
            individualCallStatus: .incomingMissed,
            tx: tx
        )
    }

    private func createOutgoingAcceptedCall(
        contactThread: TSContactThread,
        tx: SDSAnyWriteTransaction
    ) {
        createIndividualCall(
            contactThread: contactThread,
            callDirection: .outgoing,
            callType: .outgoing,
            individualCallStatus: .accepted,
            tx: tx
        )
    }

    private func createOutgoingMissedCall(
        contactThread: TSContactThread,
        tx: SDSAnyWriteTransaction
    ) {
        createIndividualCall(
            contactThread: contactThread,
            callDirection: .outgoing,
            callType: .outgoingIncomplete,
            individualCallStatus: .notAccepted,
            tx: tx
        )
    }

    private func createIndividualCall(
        contactThread: TSContactThread,
        callDirection: CallRecord.CallDirection,
        callType: RPRecentCallType,
        individualCallStatus: CallRecord.CallStatus.IndividualCallStatus,
        tx: SDSAnyWriteTransaction
    ) {
        let callInteraction = TSCall(
            callType: callType,
            offerType: .audio,
            thread: contactThread,
            sentAtTimestamp: nowTimestamp
        )
        callInteraction.anyInsert(transaction: tx)

        let callRecord = CallRecord(
            callId: .maxRandom,
            interactionRowId: callInteraction.sqliteRowId!,
            threadRowId: contactThread.sqliteRowId!,
            callType: .audioCall,
            callDirection: callDirection,
            callStatus: .individual(individualCallStatus),
            callBeganTimestamp: callInteraction.timestamp
        )
        _ = callRecordStore.insert(callRecord: callRecord, tx: tx.asV2Write)
    }

    // MARK: Group calls

    private func createGenericCall(
        groupThread: TSGroupThread,
        tx: SDSAnyWriteTransaction
    ) {
        createGroupCall(
            groupThread: groupThread,
            callDirection: .incoming,
            groupCallStatus: .generic,
            tx: tx
        )
    }

    private func createJoinedCall(
        groupThread: TSGroupThread,
        tx: SDSAnyWriteTransaction
    ) {
        createGroupCall(
            groupThread: groupThread,
            callDirection: .incoming,
            groupCallStatus: .joined,
            tx: tx
        )
    }

    private func createRingingAcceptedCall(
        groupThread: TSGroupThread,
        tx: SDSAnyWriteTransaction
    ) {
        createGroupCall(
            groupThread: groupThread,
            callDirection: .incoming,
            groupCallStatus: .ringingAccepted,
            tx: tx
        )
    }

    private func createRingingDeclinedCall(
        groupThread: TSGroupThread,
        tx: SDSAnyWriteTransaction
    ) {
        createGroupCall(
            groupThread: groupThread,
            callDirection: .incoming,
            groupCallStatus: .ringingDeclined,
            tx: tx
        )
    }

    private func createOutgoingRingingCall(
        groupThread: TSGroupThread,
        tx: SDSAnyWriteTransaction
    ) {
        createGroupCall(
            groupThread: groupThread,
            callDirection: .outgoing,
            groupCallStatus: .ringingAccepted,
            tx: tx
        )
    }

    private func createGroupCall(
        groupThread: TSGroupThread,
        callDirection: CallRecord.CallDirection,
        groupCallStatus: CallRecord.CallStatus.GroupCallStatus,
        tx: SDSAnyWriteTransaction
    ) {
        let callInteraction = OWSGroupCallMessage(
            joinedMemberAcis: [],
            creatorAci: nil,
            thread: groupThread,
            sentAtTimestamp: nowTimestamp
        )
        callInteraction.update(withHasEnded: true, transaction: tx)
        callInteraction.anyInsert(transaction: tx)

        let callRecord = CallRecord(
            callId: .maxRandom,
            interactionRowId: callInteraction.sqliteRowId!,
            threadRowId: groupThread.sqliteRowId!,
            callType: .groupCall,
            callDirection: callDirection,
            callStatus: .group(groupCallStatus),
            callBeganTimestamp: callInteraction.timestamp
        )
        _ = callRecordStore.insert(callRecord: callRecord, tx: tx.asV2Write)
    }

    // MARK: Thread enumeration

    private func enumerateThreads(
        contactThreadBlock: (
            _ thread: TSContactThread,
            _ tx: SDSAnyWriteTransaction
        ) -> Void,
        groupThreadBlock: (
            _ thread: TSGroupThread,
            _ tx: SDSAnyWriteTransaction
        ) -> Void
    ) {
        databaseStorage.write { tx in
            TSThread.anyEnumerate(transaction: tx) { thread, _ in
                if let contactThread = thread as? TSContactThread {
                    contactThreadBlock(contactThread, tx)
                } else if let groupThread = thread as? TSGroupThread {
                    groupThreadBlock(groupThread, tx)
                }
            }
        }
    }
}

#endif

private extension UInt64 {
    static var maxRandom: UInt64 {
        return UInt64.random(in: 0...UInt64.max)
    }
}
