//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public protocol CallRecordSyncMessageConversationIdAdapter {
    /// Fetch the ``CallRecord`` for the given call and conversation ID, if one
    /// exists.
    func hydrate(
        callId: UInt64,
        conversationId: CallSyncMessageConversationId,
        tx: DBReadTransaction
    ) -> CallRecord?

    /// Generates a conversation ID for use in call-related sync messages, from
    /// a ``CallRecord``.
    func getConversationId(
        callRecord: CallRecord,
        tx: DBReadTransaction
    ) -> CallSyncMessageConversationId?
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
        callId: UInt64,
        conversationId: CallSyncMessageConversationId,
        tx: DBReadTransaction
    ) -> CallRecord? {
        let threadRowId: Int64? = {
            switch conversationId {
            case .individual(let serviceId):
                guard
                    let recipient = recipientDatabaseTable.fetchRecipient(
                        serviceId: serviceId, transaction: tx
                    ),
                    let contactThread = threadStore.fetchContactThread(
                        recipient: recipient, tx: tx
                    )
                else { return nil }

                return contactThread.sqliteRowId!
            case .group(let groupId):
                return threadStore.fetchGroupThread(
                    groupId: groupId, tx: tx
                )?.sqliteRowId!
            }
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
    ) -> CallSyncMessageConversationId? {
        guard let callThread = threadStore.fetchThread(
            rowId: callRecord.threadRowId, tx: tx
        ) else { return nil }

        if
            let contactThread = callThread as? TSContactThread,
            let contactServiceId = recipientDatabaseTable.fetchServiceId(
                contactThread: contactThread, tx: tx
            )
        {
            return .individual(contactServiceId: contactServiceId)
        } else if let groupThread = callThread as? TSGroupThread {
            return .group(groupId: groupThread.groupId)
        }

        owsFailBeta("Unexpected thread type for call record!")
        return nil
    }
}
