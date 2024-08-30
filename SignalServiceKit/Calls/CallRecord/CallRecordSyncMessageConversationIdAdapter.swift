//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public protocol CallRecordSyncMessageConversationIdAdapter {
    /// Fetch the ``CallRecord`` for the given call and conversation ID, if one
    /// exists.
    func hydrate(
        conversationId: Data,
        callId: UInt64,
        tx: DBReadTransaction
    ) -> CallRecord?

    /// Generates a conversation ID for use in call-related sync messages, from
    /// a ``CallRecord``.
    func getConversationId(
        callRecord: CallRecord,
        tx: DBReadTransaction
    ) -> Data?
}

class CallRecordSyncMessageConversationIdAdapterImpl: CallRecordSyncMessageConversationIdAdapter {

    private let callRecordStore: CallRecordStore
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let threadStore: ThreadStore

    init(
        callRecordStore: CallRecordStore,
        recipientDatabaseTable: RecipientDatabaseTable,
        threadStore: ThreadStore
    ) {
        self.callRecordStore = callRecordStore
        self.recipientDatabaseTable = recipientDatabaseTable
        self.threadStore = threadStore
    }

    // MARK: -

    func hydrate(
        conversationId: Data,
        callId: UInt64,
        tx: DBReadTransaction
    ) -> CallRecord? {
        let threadRowId = { () -> Int64? in
            if let serviceId = try? ServiceId.parseFrom(serviceIdBinary: conversationId) {
                guard
                    let recipient = recipientDatabaseTable.fetchRecipient(serviceId: serviceId, transaction: tx),
                    let contactThread = threadStore.fetchContactThread(recipient: recipient, tx: tx)
                else {
                    return nil
                }
                return contactThread.sqliteRowId!
            }
            // [CallLink] TODO: Generalize this because group IDs/room IDs are ambiguous.
            if let groupId = try? GroupIdentifier(contents: [UInt8](conversationId)) {
                return threadStore.fetchGroupThread(groupId: groupId.serialize().asData, tx: tx)?.sqliteRowId!
            }
            return nil
        }()

        guard let threadRowId else { return nil }

        return callRecordStore.fetch(
            callId: callId,
            threadRowId: threadRowId,
            tx: tx
        ).unwrapped
    }

    func getConversationId(
        callRecord: CallRecord,
        tx: DBReadTransaction
    ) -> Data? {
        // [CallLink] TODO: Generalize this because group IDs/room IDs are ambiguous.
        guard let callThread = threadStore.fetchThread(rowId: callRecord.threadRowId, tx: tx) else {
            return nil
        }

        if
            let contactThread = callThread as? TSContactThread,
            let contactServiceId = recipientDatabaseTable.fetchServiceId(contactThread: contactThread, tx: tx)
        {
            return contactServiceId.serviceIdBinary.asData
        } else if let groupThread = callThread as? TSGroupThread {
            return groupThread.groupId
        }

        owsFailBeta("Unexpected thread type for call record!")
        return nil
    }
}
